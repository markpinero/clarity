import AppKit
import ClarityBreaks
import Observation

@MainActor
@Observable
final class BreakController {
  private(set) var snapshot: BreakSnapshot
  private(set) var configuration: BreakConfiguration
  private(set) var now = Date()
  private(set) var lastError: String?

  var isEnabled: Bool { configuration.isEnabled }

  var phaseLabel: String {
    guard isEnabled else { return "Breaks Disabled" }
    return switch snapshot.phase {
    case .stopped: "Breaks Off"
    case .focusing: "Focus"
    case .countdown: "Break Soon"
    case .breaking: snapshot.breakKind == .long ? "Long Break" : "Eye Break"
    case .paused: "Breaks Paused"
    }
  }

  var remainingSeconds: Int? {
    snapshot.remaining(at: now).map { Int(ceil($0)) }
  }

  var isRunning: Bool {
    ![BreakPhase.stopped, .paused].contains(snapshot.phase)
  }

  var isManuallyPaused: Bool {
    snapshot.pauseReasons.contains(.manual)
  }

  var activePauseReasons: [BreakPauseReason] {
    snapshot.pauseReasons.sorted { $0.name < $1.name }
  }

  private let store: any BreakStore
  private let presenter: BreakOverlayPresenter
  let contextMonitor: BreakContextMonitor
  private var contextResolver = BreakContextResolver()
  private var timer: Timer?
  private var screenObserver: NSObjectProtocol?

  init(
    store: any BreakStore = UserDefaultsBreakStore(),
    presenter: BreakOverlayPresenter = BreakOverlayPresenter(),
    contextMonitor: BreakContextMonitor = BreakContextMonitor()
  ) {
    self.store = store
    self.presenter = presenter
    self.contextMonitor = contextMonitor
    let document = store.load()
    snapshot = document.snapshot
    configuration = document.configuration
  }

  func startRuntime() {
    guard timer == nil else { return }
    let now = Date()
    self.now = now
    let effects =
      isEnabled
      ? BreakReducer.recover(&snapshot, now: now, configuration: configuration)
      : BreakReducer.reduce(&snapshot, event: .stop, configuration: configuration)
    process(effects)
    if !effects.contains(.presentCountdown), !effects.contains(.presentBreak) {
      presentCurrentOverlay()
    }

    contextMonitor.onChange = { [weak self] observation in
      self?.applyContext(observation)
    }
    contextMonitor.start()

    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, [.countdown, .breaking].contains(snapshot.phase) else { return }
        presentCurrentOverlay()
      }
    }
  }

  func shutdown() {
    timer?.invalidate()
    timer = nil
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    contextMonitor.stop()
    presenter.dismiss()
    persist()
  }

  func startCycle() {
    guard isEnabled else { return }
    send(.start(.now))
    applyContext(contextMonitor.observation)
  }
  func startBreakNow() {
    guard isEnabled else { return }
    send(.startBreak(.now))
  }
  func stopCycle() { send(.stop) }
  func reset() {
    guard isEnabled else { return }
    send(.reset)
  }
  func snooze() { send(.snooze(.now)) }
  func skip() { send(.skip(.now)) }

  func togglePause() {
    if isManuallyPaused {
      send(.resume(.now))
    } else {
      send(.pause(.now))
    }
  }

  func requestContextPermission(_ permission: ContextPermission) {
    contextMonitor.requestContextPermission(permission)
  }

  func setEnabled(_ isEnabled: Bool) {
    guard configuration.isEnabled != isEnabled else { return }
    configuration.isEnabled = isEnabled
    if !isEnabled {
      send(.stop)
    }
    persist()
  }

  func updateConfiguration(_ update: (inout BreakConfiguration) -> Void) {
    update(&configuration)
    configuration = BreakConfiguration(
      isEnabled: configuration.isEnabled,
      focusDuration: configuration.focusDuration,
      shortBreakDuration: configuration.shortBreakDuration,
      longBreakDuration: configuration.longBreakDuration,
      longBreakEvery: configuration.longBreakEvery,
      countdownDuration: configuration.countdownDuration,
      snoozeDuration: configuration.snoozeDuration,
      idleResetEnabled: configuration.idleResetEnabled,
      idleResetDuration: configuration.idleResetDuration,
      pauseDuringCalendarMeetings: configuration.pauseDuringCalendarMeetings,
      pauseDuringCalls: configuration.pauseDuringCalls,
      pauseDuringVideoPlayback: configuration.pauseDuringVideoPlayback,
      pauseDuringGaming: configuration.pauseDuringGaming,
      pauseDuringScreenSharing: configuration.pauseDuringScreenSharing
    )
    persist()
    applyContext(contextMonitor.observation)
  }

  private func tick() {
    tick(at: .now)
  }

  func tick(at now: Date) {
    self.now = now
    var nextSnapshot = snapshot
    let effects = BreakReducer.reduce(
      &nextSnapshot,
      event: .tick(now),
      configuration: configuration
    )
    if nextSnapshot != snapshot {
      snapshot = nextSnapshot
    }
    process(effects)
    if [.countdown, .breaking].contains(snapshot.phase) {
      presenter.update(snapshot: snapshot, now: now)
    }
  }

  private func send(_ event: BreakEvent) {
    now = .now
    let effects = BreakReducer.reduce(
      &snapshot,
      event: event,
      configuration: configuration
    )
    process(effects)
  }

  private func applyContext(_ observation: BreakContextObservation) {
    let resolution = contextResolver.resolve(observation, configuration: configuration)
    send(
      .contextChanged(
        .now,
        reasons: resolution.reasons,
        resetFocusAfterIdle: resolution.resetFocusAfterIdle
      )
    )
  }

  private func process(_ effects: [BreakEffect]) {
    for effect in effects {
      switch effect {
      case .persist:
        persist()
      case .presentCountdown:
        presentCountdown()
      case .presentBreak:
        presentBreak()
      case .dismissBreak:
        presenter.dismiss()
      }
    }
  }

  private func presentCurrentOverlay() {
    switch snapshot.phase {
    case .countdown:
      presentCountdown()
    case .breaking:
      presentBreak()
    case .stopped, .focusing, .paused:
      presenter.dismiss()
    }
  }

  private func presentCountdown() {
    presenter.presentCountdown(
      snapshot: snapshot,
      now: now,
      countdownSeconds: Int(configuration.countdownDuration),
      snoozeMinutes: Int(configuration.snoozeDuration / 60),
      onSnooze: { [weak self] in self?.snooze() },
      onSkip: { [weak self] in self?.skip() }
    )
  }

  private func presentBreak() {
    let totalSeconds =
      snapshot.breakKind == .long
      ? configuration.longBreakDuration
      : configuration.shortBreakDuration
    presenter.presentBreak(
      snapshot: snapshot,
      now: now,
      totalSeconds: Int(totalSeconds),
      snoozeMinutes: Int(configuration.snoozeDuration / 60),
      onSnooze: { [weak self] in self?.snooze() },
      onSkip: { [weak self] in self?.skip() },
      onEmergencyEscape: { [weak self] in self?.stopCycle() }
    )
  }

  private func persist() {
    do {
      try store.save(BreakStateDocument(configuration: configuration, snapshot: snapshot))
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }
}
