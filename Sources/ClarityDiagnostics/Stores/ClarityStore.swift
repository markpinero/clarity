import AppKit
import ClarityBreaks
import ClarityCore
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
final class ClarityStore: ObservableObject {
  static let shared = ClarityStore()

  @Published private(set) var preferences: AppPreferences
  @Published private(set) var displays: [DisplayDescriptor] = []
  @Published private(set) var driverMode: DisplayCoordinatorMode = .idle
  @Published private(set) var decision: DisplayPolicyDecision
  @Published private(set) var lastError: String?
  @Published private(set) var events: [ClarityEvent] = []
  @Published private(set) var now = Date()
  @Published private(set) var locationState: OneShotLocationProvider.State = .idle
  @Published private(set) var loginItemState: LoginItemService.State = .disabled
  @Published private(set) var activeApplication = ActiveApplicationMonitor.State.unavailable
  let breakController: BreakController

  var isEnabled: Bool { preferences.isEnabled }
  var isPaused: Bool { preferences.isPaused }
  var controlMode: ControlMode { preferences.controlMode }
  var selectedProfile: ClarityProfile { preferences.selectedProfile }
  var schedule: ClockSchedule { preferences.schedule }
  var automaticScheduleKind: AutomaticScheduleKind { preferences.automaticScheduleKind }
  var solarSchedule: SolarSchedule { preferences.solarSchedule }
  var solarLocation: SolarLocationSettings { preferences.solarLocation }
  var supportedDisplayCount: Int { displays.filter(\.supportsGamma).count }
  var activeAppRules: [ActiveAppRule] { preferences.activeAppRules }
  var pauseInFullscreen: Bool { preferences.pauseInFullscreen }
  var hideFromAppSwitcher: Bool { preferences.hideFromAppSwitcher }
  let panicResetHotKeyLabel = "⌃⌥⌘R"

  var currentAdjustment: DisplayAdjustment? { decision.adjustment }

  var currentSolarEvents: SolarEvents? {
    guard case .solar(let events, _) = decision.scheduleBasis else { return nil }
    return events
  }

  var schedulePreview: SchedulePreview {
    if automaticScheduleKind == .solar, let events = currentSolarEvents {
      return .solar(
        schedule: solarSchedule,
        sunriseMinute: events.sunriseMinute,
        sunsetMinute: events.sunsetMinute,
        moonPhase: MoonCalculator.illuminatedFraction(at: now)
      )
    }
    return .clock(schedule: schedule)
  }

  var currentMinute: Double {
    Self.minuteOfDay(now)
  }

  var statusLabel: String {
    switch decision.source {
    case .disabled: "Off"
    case .paused: "Paused"
    case .manual(let profile): profile.name
    case .automatic(let phase): phase.shortLabel
    case .automationPaused(.fullscreen): "Paused for Full Screen"
    case .automationPaused(.activeApplication): "Paused for App"
    case .automationProfile(let profile, _): profile.name
    }
  }

  var menuBarTitle: String {
    guard let adjustment = currentAdjustment else {
      return statusLabel
    }
    return "\(adjustment.kelvin) K"
  }

  private let coordinator: DisplayCoordinator
  private let topologyMonitor: DisplayTopologyMonitor
  private let repository: PreferencesRepository
  private let locationProvider: OneShotLocationProvider
  private let loginItemService: LoginItemService
  private let activeApplicationMonitor: ActiveApplicationMonitor
  private let globalHotKeyMonitor: GlobalHotKeyMonitor
  private var wakeObservers: [NSObjectProtocol] = []
  private var scheduleTimer: Timer?
  private var rampTimer: Timer?
  private var started = false
  private let logger = Logger(
    subsystem: "com.markpinero.Clarity",
    category: "runtime"
  )

  private init() {
    let legacyDefaults =
      Bundle.main.bundleIdentifier == "com.markpinero.Clarity"
      ? UserDefaults(suiteName: "com.markpinero.IrisAlternative")
      : nil
    let repository = PreferencesRepository(legacyDefaults: legacyDefaults)
    let preferences = repository.load()
    self.repository = repository
    self.preferences = preferences
    self.decision = DisplayPolicy.resolve(preferences: preferences, at: .now)
    coordinator = DisplayCoordinator(driver: CoreGraphicsDisplayDriver())
    topologyMonitor = DisplayTopologyMonitor()
    locationProvider = OneShotLocationProvider()
    loginItemService = LoginItemService()
    activeApplicationMonitor = ActiveApplicationMonitor()
    globalHotKeyMonitor = GlobalHotKeyMonitor()
    breakController = BreakController(
      store: UserDefaultsBreakStore(legacyDefaults: legacyDefaults)
    )
    loginItemState = loginItemService.state
  }

  func start() {
    guard !started else { return }
    started = true

    locationProvider.onStateChange = { [weak self] state in
      guard let self else { return }
      locationState = state
      guard case .located(let coordinate) = state else { return }
      preferences.solarLocation.automaticCoordinate = coordinate
      persistAndEvaluate(reason: "Updated coarse solar location", force: true)
    }

    refreshDisplays(reason: "Initial display probe", forceApply: true, timing: .instant)
    startContextAutomation()
    startGlobalHotKey()
    breakController.startRuntime()
    startTopologyMonitoring()
    startWakeMonitoring()
    startScheduleTimer()
  }

  func setEnabled(_ enabled: Bool) {
    preferences.isEnabled = enabled
    if !enabled {
      preferences.isPaused = false
    }
    persistAndEvaluate(reason: enabled ? "Enabled Clarity" : "Disabled Clarity", force: true)
  }

  func setControlMode(_ mode: ControlMode) {
    preferences.controlMode = mode
    preferences.isPaused = false
    persistAndEvaluate(reason: "Changed mode to \(mode.name)", force: true)
  }

  func activateProfile(_ profile: ClarityProfile) {
    preferences.selectedProfile = profile
    preferences.controlMode = .manual
    preferences.isPaused = false
    persistAndEvaluate(reason: "Selected \(profile.name) profile", force: true)
  }

  func togglePause() {
    guard isEnabled else { return }
    preferences.isPaused.toggle()
    persistAndEvaluate(
      reason: preferences.isPaused ? "Paused Clarity" : "Resumed Clarity",
      force: true
    )
  }

  func reset() {
    preferences.isEnabled = false
    preferences.isPaused = false
    let persistenceError = persist()
    refreshDecision()

    perform("Reset") {
      try coordinator.reset(timing: .manual)
      pumpRamp()
      driverMode = coordinator.mode
      record("Restored captured display tables and turned Clarity off.")
    }
    if let persistenceError {
      lastError = persistenceError
    }
  }

  func updateDayStartMinute(_ minute: Int) {
    updateSchedule(dayStartMinute: minute)
  }

  func updateNightStartMinute(_ minute: Int) {
    updateSchedule(nightStartMinute: minute)
  }

  func updateTransitionMinutes(_ minutes: Int) {
    updateSchedule(transitionMinutes: minutes)
  }

  func updateDayProfile(_ profile: ClarityProfile) {
    updateSchedule(dayProfile: profile)
  }

  func updateNightProfile(_ profile: ClarityProfile) {
    updateSchedule(nightProfile: profile)
  }

  func setAutomaticScheduleKind(_ kind: AutomaticScheduleKind) {
    preferences.automaticScheduleKind = kind
    persistAndEvaluate(reason: "Changed automatic schedule to \(kind.name)", force: true)
  }

  func setSolarLocationSource(_ source: SolarLocationSource) {
    preferences.solarLocation.source = source
    persistAndEvaluate(reason: "Changed solar location source", force: true)
  }

  func requestOneTimeLocation() {
    locationProvider.requestLocation()
  }

  func updateManualLatitude(_ latitude: Double) {
    let current =
      preferences.solarLocation.manualCoordinate
      ?? preferences.solarLocation.automaticCoordinate
      ?? GeographicCoordinate(latitude: 0, longitude: 0)
    updateManualCoordinate(
      GeographicCoordinate(latitude: latitude, longitude: current.longitude)
    )
  }

  func updateManualLongitude(_ longitude: Double) {
    let current =
      preferences.solarLocation.manualCoordinate
      ?? preferences.solarLocation.automaticCoordinate
      ?? GeographicCoordinate(latitude: 0, longitude: 0)
    updateManualCoordinate(
      GeographicCoordinate(latitude: current.latitude, longitude: longitude)
    )
  }

  func updateSolarTransitionMinutes(_ minutes: Int) {
    updateSolarSchedule(transitionMinutes: minutes)
  }

  func updateSolarDayProfile(_ profile: ClarityProfile) {
    updateSolarSchedule(dayProfile: profile)
  }

  func updateSolarNightProfile(_ profile: ClarityProfile) {
    updateSolarSchedule(nightProfile: profile)
  }

  func updateSolarSleepProfile(_ profile: ClarityProfile) {
    updateSolarSchedule(sleepProfile: profile)
  }

  func setSolarSleepEnabled(_ isEnabled: Bool) {
    updateSolarSchedule(usesSleepAdjustment: isEnabled)
  }

  func updateSolarBedtimeMinute(_ minute: Int) {
    updateSolarSchedule(bedtimeMinute: minute)
  }

  func updateSolarWakeMinute(_ minute: Int) {
    updateSolarSchedule(wakeMinute: minute)
  }

  func displaySettings(for stableID: String) -> DisplaySettings {
    preferences.displaySettings[stableID] ?? .standard
  }

  func setDisplayEnabled(_ enabled: Bool, stableID: String) {
    var settings = displaySettings(for: stableID)
    settings.isEnabled = enabled
    preferences.displaySettings[stableID] = settings == .standard ? nil : settings
    persistAndEvaluate(reason: "Changed display enablement", force: true)
  }

  func setDisplayProfileOverride(_ profile: ClarityProfile?, stableID: String) {
    var settings = displaySettings(for: stableID)
    settings.profileOverride = profile
    preferences.displaySettings[stableID] = settings == .standard ? nil : settings
    persistAndEvaluate(reason: "Changed display profile override", force: true)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    loginItemService.setEnabled(enabled)
    loginItemState = loginItemService.state
    if case .failed(let message) = loginItemState {
      lastError = "Could not update launch at login: \(message)"
    }
  }

  func openLoginItemSettings() {
    loginItemService.openSystemSettings()
  }

  func setPauseInFullscreen(_ isEnabled: Bool) {
    preferences.pauseInFullscreen = isEnabled
    persistAndEvaluate(reason: "Updated full-screen automation", force: true)
  }

  func setHideFromAppSwitcher(_ isHidden: Bool) {
    preferences.hideFromAppSwitcher = isHidden
    let persistenceError = persist()
    applyAppVisibility()
    if let persistenceError {
      lastError = persistenceError
    }
  }

  func moveToMenuBarOnly() {
    setHideFromAppSwitcher(true)
    NSApp.hide(nil)
  }

  func applyAppVisibility() {
    NSApp.setActivationPolicy(hideFromAppSwitcher ? .accessory : .regular)
  }

  func addActiveAppRule(
    bundleIdentifier: String,
    displayName: String,
    action: ActiveAppAction
  ) {
    let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleIdentifier.isEmpty else {
      lastError = "Enter an application bundle identifier."
      return
    }
    let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    preferences.activeAppRules.removeAll {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
    preferences.activeAppRules.append(
      ActiveAppRule(
        bundleIdentifier: bundleIdentifier,
        displayName: displayName.isEmpty ? bundleIdentifier : displayName,
        action: action
      )
    )
    persistAndEvaluate(reason: "Added active-app automation", force: true)
  }

  func updateActiveAppRule(id: UUID, action: ActiveAppAction) {
    guard let index = preferences.activeAppRules.firstIndex(where: { $0.id == id }) else {
      return
    }
    preferences.activeAppRules[index].action = action
    persistAndEvaluate(reason: "Updated active-app automation", force: true)
  }

  func removeActiveAppRule(id: UUID) {
    preferences.activeAppRules.removeAll { $0.id == id }
    persistAndEvaluate(reason: "Removed active-app automation", force: true)
  }

  func exportSettings() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "clarity-settings.json"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          try SettingsDocument.encode(preferences).write(to: url, options: .atomic)
          lastError = nil
          record("Exported settings to \(url.lastPathComponent).")
        } catch {
          lastError = "Could not export settings: \(error.localizedDescription)"
        }
      }
    }
  }

  func importSettings() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          var imported = try SettingsDocument.decode(Data(contentsOf: url))
          imported.isEnabled = false
          imported.isPaused = false
          preferences = imported
          persistAndEvaluate(reason: "Imported settings in the Off state", force: true)
          applyAppVisibility()
        } catch {
          lastError = "Could not import settings: \(error.localizedDescription)"
        }
      }
    }
  }

  func refreshDisplays(reason: String, forceApply: Bool = false, timing: RampTiming = .manual) {
    do {
      try coordinator.refreshDisplays()
      displays = coordinator.displays
      driverMode = coordinator.mode
      lastError = nil
      record(
        "Found \(displays.count) online display(s); \(supportedDisplayCount) support gamma tables."
      )
    } catch {
      lastError = error.localizedDescription
      record("\(reason) failed: \(error.localizedDescription)", level: .error)
      return
    }

    evaluatePolicy(reason: reason, force: forceApply, shouldLog: false, timing: timing)
  }

  func restoreForTermination() {
    scheduleTimer?.invalidate()
    scheduleTimer = nil
    rampTimer?.invalidate()
    rampTimer = nil
    topologyMonitor.stop()
    activeApplicationMonitor.stop()
    globalHotKeyMonitor.stop()
    breakController.shutdown()

    let center = NSWorkspace.shared.notificationCenter
    wakeObservers.forEach(center.removeObserver)
    wakeObservers.removeAll()

    do {
      try coordinator.reset(timing: .instant)
      logger.info("Restored display tables during application termination.")
    } catch {
      logger.error(
        "Display restoration during termination failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func updateSchedule(
    dayStartMinute: Int? = nil,
    nightStartMinute: Int? = nil,
    transitionMinutes: Int? = nil,
    dayProfile: ClarityProfile? = nil,
    nightProfile: ClarityProfile? = nil
  ) {
    let current = preferences.schedule
    preferences.schedule = ClockSchedule(
      dayStartMinute: dayStartMinute ?? current.dayStartMinute,
      nightStartMinute: nightStartMinute ?? current.nightStartMinute,
      transitionMinutes: transitionMinutes ?? current.transitionMinutes,
      dayProfile: dayProfile ?? current.dayProfile,
      nightProfile: nightProfile ?? current.nightProfile
    )
    persistAndEvaluate(reason: "Updated automatic schedule", force: controlMode == .automatic)
  }

  private func updateSolarSchedule(
    transitionMinutes: Int? = nil,
    dayProfile: ClarityProfile? = nil,
    nightProfile: ClarityProfile? = nil,
    sleepProfile: ClarityProfile? = nil,
    usesSleepAdjustment: Bool? = nil,
    bedtimeMinute: Int? = nil,
    wakeMinute: Int? = nil
  ) {
    let current = preferences.solarSchedule
    preferences.solarSchedule = SolarSchedule(
      transitionMinutes: transitionMinutes ?? current.transitionMinutes,
      dayProfile: dayProfile ?? current.dayProfile,
      nightProfile: nightProfile ?? current.nightProfile,
      sleepProfile: sleepProfile ?? current.sleepProfile,
      usesSleepAdjustment: usesSleepAdjustment ?? current.usesSleepAdjustment,
      bedtimeMinute: bedtimeMinute ?? current.bedtimeMinute,
      wakeMinute: wakeMinute ?? current.wakeMinute,
      dayTransitionMinutes: transitionMinutes ?? current.dayTransitionMinutes,
      nightTransitionMinutes: transitionMinutes ?? current.nightTransitionMinutes,
      sleepTransitionMinutes: transitionMinutes ?? current.sleepTransitionMinutes,
      newMoonOffsetSeconds: current.newMoonOffsetSeconds,
      fullMoonOffsetSeconds: current.fullMoonOffsetSeconds
    )
    persistAndEvaluate(reason: "Updated solar schedule", force: controlMode == .automatic)
  }

  private func updateManualCoordinate(_ coordinate: GeographicCoordinate) {
    preferences.solarLocation.manualCoordinate = coordinate
    persistAndEvaluate(reason: "Updated manual solar location", force: true)
  }

  private func persistAndEvaluate(reason: String, force: Bool) {
    let persistenceError = persist()
    evaluatePolicy(reason: reason, force: force, shouldLog: true)
    if let persistenceError {
      lastError = persistenceError
    }
  }

  private func persist() -> String? {
    do {
      try repository.save(preferences)
      return nil
    } catch {
      let message = "Could not save settings: \(error.localizedDescription)"
      record(message, level: .error)
      return message
    }
  }

  private func evaluatePolicy(
    reason: String,
    force: Bool,
    shouldLog: Bool,
    timing: RampTiming = .manual
  ) {
    now = .now
    refreshDecision()

    perform(reason) {
      guard let adjustment = decision.adjustment else {
        if coordinator.mode != .idle {
          try coordinator.reset(timing: timing)
          pumpRamp()
        }
        driverMode = coordinator.mode
        if shouldLog {
          record(
            decision.source == .paused ? "Paused and restored display tables." : "Clarity is off.")
        }
        return
      }

      let supportedIDs = Set(displays.filter(\.supportsGamma).map(\.id.stableID))
      guard !supportedIDs.isEmpty else {
        throw ClarityStoreError.noSupportedDisplays
      }
      let targets = DisplayPolicy.targetAdjustments(
        globalAdjustment: adjustment,
        stableIDs: supportedIDs,
        displaySettings: preferences.displaySettings
      )

      if !force, case .applied(let current) = coordinator.mode, current == targets {
        driverMode = coordinator.mode
        return
      }

      try coordinator.apply(adjustments: targets, timing: timing)
      pumpRamp()
      driverMode = coordinator.mode
      if shouldLog {
        record(
          "Applied policy to \(targets.count) of \(supportedIDs.count) supported display(s)."
        )
      }
    }
  }

  private func pumpRamp() {
    do {
      let status = try coordinator.advanceRamp()
      driverMode = coordinator.mode
      if status.isLive {
        scheduleRampTimer(interval: status.nextInterval)
      } else {
        rampTimer?.invalidate()
        rampTimer = nil
      }
    } catch {
      rampTimer?.invalidate()
      rampTimer = nil
      driverMode = coordinator.mode
      lastError = error.localizedDescription
      record("Display ramp failed: \(error.localizedDescription)", level: .error)
    }
  }

  private func scheduleRampTimer(interval: TimeInterval) {
    guard rampTimer == nil else { return }
    let timer = Timer(timeInterval: max(interval, 1.0 / 60), repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.pumpRamp() }
    }
    RunLoop.main.add(timer, forMode: .common)
    rampTimer = timer
  }

  private func refreshDecision() {
    decision = DisplayPolicy.resolve(
      preferences: preferences,
      at: now,
      context: AutomationContext(
        activeApplicationBundleIdentifier: activeApplication.bundleIdentifier,
        isActiveApplicationFullscreen: FullscreenDetector.isFullscreen(
          processIdentifier: activeApplication.processIdentifier
        )
      )
    )
  }

  private func startContextAutomation() {
    activeApplicationMonitor.onChange = { [weak self] state in
      guard let self else { return }
      activeApplication = state
      evaluatePolicy(reason: "Active application changed", force: true, shouldLog: false)
    }
    activeApplicationMonitor.start()
    record("Monitoring the active application without storing application history.")
  }

  private func startGlobalHotKey() {
    perform("Register panic-reset hotkey") {
      try globalHotKeyMonitor.start { [weak self] in
        self?.reset()
      }
      record("Panic reset is available globally at \(panicResetHotKeyLabel).")
    }
  }

  private func startScheduleTimer() {
    let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.evaluatePolicy(
          reason: "Schedule tick", force: false, shouldLog: false, timing: .schedule)
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    scheduleTimer = timer
    record("Automatic schedule updates every 30 seconds.")
  }

  private func startTopologyMonitoring() {
    perform("Start topology monitoring") {
      try topologyMonitor.start { [weak self] in
        Task { @MainActor [weak self] in
          self?.refreshDisplays(reason: "Display topology changed", forceApply: true)
        }
      }
      record("Monitoring display add, remove, mode, and configuration events.")
    }
  }

  private func startWakeMonitoring() {
    let center = NSWorkspace.shared.notificationCenter
    let names: [Notification.Name] = [
      NSWorkspace.didWakeNotification,
      NSWorkspace.screensDidWakeNotification,
    ]

    wakeObservers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshDisplays(
            reason: "System or displays woke", forceApply: true, timing: .instant)
        }
      }
    }
    record("Monitoring system and display wake notifications.")
  }

  private func perform(_ action: String, operation: () throws -> Void) {
    do {
      try operation()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
      record("\(action) failed: \(error.localizedDescription)", level: .error)
    }
  }

  private func record(_ message: String, level: ClarityEvent.Level = .info) {
    events.insert(ClarityEvent(timestamp: .now, level: level, message: message), at: 0)
    events = Array(events.prefix(30))

    switch level {
    case .info:
      logger.info("\(message, privacy: .public)")
    case .error:
      logger.error("\(message, privacy: .public)")
    }
  }

  private static func minuteOfDay(_ date: Date = .now) -> Double {
    let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
      + Double(components.second ?? 0) / 60
  }
}

struct ClarityEvent: Identifiable, Equatable {
  enum Level: String {
    case info
    case error
  }

  let id = UUID()
  let timestamp: Date
  let level: Level
  let message: String
}

private enum ClarityStoreError: LocalizedError {
  case noSupportedDisplays

  var errorDescription: String? {
    "No online displays expose gamma transfer tables."
  }
}

extension SchedulePhase {
  fileprivate var shortLabel: String {
    switch self {
    case .day: "Day"
    case .night: "Night"
    case .transitionToDay: "To Day"
    case .transitionToNight: "To Night"
    case .transitionToSleep: "To Sleep"
    case .sleep: "Sleep"
    case .transitionFromSleep: "Waking"
    }
  }
}
