import AppKit
import ApplicationServices
import ClarityBreaks
import Combine
import CoreAudio
import CoreGraphics
import CoreMediaIO
import EventKit
import GameController
import IOKit.pwr_mgt

@MainActor
final class BreakContextMonitor: ObservableObject {
  @Published private(set) var observation = BreakContextObservation()
  @Published private(set) var signalDetails: [BreakPauseReason: String] = [:]
  @Published private(set) var accessibilityPermission = ContextPermissionState.notDetermined
  @Published private(set) var screenRecordingPermission = ContextPermissionState.notDetermined
  @Published private(set) var calendarPermission = ContextPermissionState.notDetermined
  var onChange: ((BreakContextObservation) -> Void)?

  private let eventStore = EKEventStore()
  private let permissionRequestHistory = ContextPermissionRequestHistory()
  private var timer: Timer?
  private var cachedCalendarMeeting = false
  private var lastCalendarScan = Date.distantPast

  func start() {
    guard timer == nil else { return }
    refreshPermissionState()
    poll()
    let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func requestContextPermission(_ permission: ContextPermission) {
    refreshPermissionState()
    switch ContextPermissionPlan.action(for: permissionState(for: permission)) {
    case .requestSystemPermission:
      permissionRequestHistory.markRequested(permission)
      NSApp.activate(ignoringOtherApps: true)
      requestSystemPermission(permission)
    case .openSystemSettings:
      openSystemSettings(for: permission)
    case .none:
      break
    }
  }

  func refreshPermissionState() {
    accessibilityPermission = permissionState(
      isGranted: AXIsProcessTrusted(),
      permission: .accessibility
    )
    screenRecordingPermission = permissionState(
      isGranted: CGPreflightScreenCaptureAccess(),
      permission: .screenRecording
    )
    calendarPermission = Self.calendarPermissionState()
  }

  private func requestSystemPermission(_ permission: ContextPermission) {
    switch permission {
    case .calendar:
      requestCalendarPermission()
    case .accessibility:
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
      refreshPermissionState()
    case .screenRecording:
      guard !CGPreflightScreenCaptureAccess() else { return }
      _ = CGRequestScreenCaptureAccess()
      refreshPermissionState()
    }
  }

  private func requestCalendarPermission() {
    guard Self.calendarPermissionState() == .notDetermined else { return }
    if #available(macOS 14.0, *) {
      eventStore.requestFullAccessToEvents { [weak self] _, _ in
        Task { @MainActor [weak self] in
          self?.refreshCalendarPermissionAfterRequest()
        }
      }
    } else {
      eventStore.requestAccess(to: .event) { [weak self] _, _ in
        Task { @MainActor [weak self] in
          self?.refreshCalendarPermissionAfterRequest()
        }
      }
    }
  }

  private func refreshCalendarPermissionAfterRequest() {
    refreshPermissionState()
    lastCalendarScan = .distantPast
    poll()
  }

  private func permissionState(for permission: ContextPermission) -> ContextPermissionState {
    switch permission {
    case .calendar: calendarPermission
    case .accessibility: accessibilityPermission
    case .screenRecording: screenRecordingPermission
    }
  }

  private func permissionState(
    isGranted: Bool,
    permission: ContextPermission
  ) -> ContextPermissionState {
    if isGranted { return .granted }
    return permissionRequestHistory.contains(permission) ? .denied : .notDetermined
  }

  private func openSystemSettings(for permission: ContextPermission) {
    let privacyPane: String
    switch permission {
    case .calendar: privacyPane = "Privacy_Calendars"
    case .accessibility: privacyPane = "Privacy_Accessibility"
    case .screenRecording: privacyPane = "Privacy_ScreenCapture"
    }
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?") else {
      return
    }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = privacyPane
    if let settingsURL = components?.url {
      NSWorkspace.shared.open(settingsURL)
    }
  }

  private func poll() {
    refreshPermissionState()
    let now = Date()
    if now.timeIntervalSince(lastCalendarScan) >= 15 {
      cachedCalendarMeeting = hasCalendarMeeting(at: now)
      lastCalendarScan = now
    }

    let mediaAssertions = Self.displaySleepAssertionOwners()
    let activeCall = Self.isMicrophoneActive() || Self.isCameraActive()
    let activeApplication = NSWorkspace.shared.frontmostApplication
    let activeBundleIdentifier = activeApplication?.bundleIdentifier ?? ""
    let activeWindowTitle = activeApplication.flatMap {
      Self.frontmostWindowTitle(processIdentifier: $0.processIdentifier)
    }
    let isFullscreen =
      activeApplication.map {
        FullscreenDetector.isFullscreen(processIdentifier: $0.processIdentifier)
      } ?? false
    let activeGame = Self.isLikelyGame(
      bundleIdentifier: activeBundleIdentifier,
      isFullscreen: isFullscreen
    )
    let titleIndicatesVideo = Self.isLikelyVideoTitle(activeWindowTitle, isFullscreen: isFullscreen)
    let screenSharingApplications = Self.activeScreenSharingApplications(
      canInspectWindows: screenRecordingPermission == .granted
    )

    var details: [BreakPauseReason: String] = [:]
    if cachedCalendarMeeting { details[.calendarMeeting] = "An active calendar event" }
    if activeCall { details[.call] = "Camera or microphone activity" }
    if let owner = mediaAssertions.first {
      details[.videoPlayback] = owner
    } else if titleIndicatesVideo {
      details[.videoPlayback] = activeWindowTitle
    }
    if activeGame {
      details[.gaming] = activeApplication?.localizedName ?? activeBundleIdentifier
    }
    if let owner = screenSharingApplications.first { details[.screenSharing] = owner }

    let next = BreakContextObservation(
      idleDuration: CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: CGEventType(rawValue: UInt32.max)!
      ),
      keyboardIdleDuration: CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: .keyDown
      ),
      hasCalendarMeeting: cachedCalendarMeeting,
      hasActiveCall: activeCall,
      hasVideoPlayback: !mediaAssertions.isEmpty || titleIndicatesVideo,
      hasActiveGame: activeGame,
      isScreenSharing: !screenSharingApplications.isEmpty
    )
    signalDetails = details
    guard next != observation else { return }
    observation = next
    onChange?(next)
  }

  private func hasCalendarMeeting(at date: Date) -> Bool {
    guard calendarPermission == .granted else { return false }
    let predicate = eventStore.predicateForEvents(
      withStart: date.addingTimeInterval(-24 * 60 * 60),
      end: date.addingTimeInterval(24 * 60 * 60),
      calendars: nil
    )
    return eventStore.events(matching: predicate).contains { event in
      !event.isAllDay
        && event.status != .canceled
        && event.startDate <= date
        && event.endDate > date
    }
  }

  private static func calendarPermissionState() -> ContextPermissionState {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .authorized, .fullAccess: .granted
    case .denied: .denied
    case .restricted: .restricted
    case .notDetermined: .notDetermined
    case .writeOnly: .denied
    @unknown default: .denied
    }
  }

  private static func isMicrophoneActive() -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &device
      ) == noErr,
      device != kAudioObjectUnknown
    else {
      return false
    }

    address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
      && running != 0
  }

  private static func isCameraActive() -> Bool {
    var address = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var dataSize: UInt32 = 0
    guard
      CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize
      ) == noErr,
      dataSize > 0
    else {
      return false
    }

    var devices = [CMIOObjectID](
      repeating: 0,
      count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size
    )
    guard
      CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        dataSize,
        &dataSize,
        &devices
      ) == noErr
    else {
      return false
    }

    address = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    return devices.contains { device in
      var running: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size)
      return CMIOObjectGetPropertyData(
        device,
        &address,
        0,
        nil,
        size,
        &size,
        &running
      ) == noErr && running != 0
    }
  }

  private static func displaySleepAssertionOwners() -> [String] {
    var unmanaged: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess, let unmanaged else {
      return []
    }
    let assertionsByProcess = unmanaged.takeRetainedValue() as NSDictionary
    var owners: [String] = []
    for case let assertions as [NSDictionary] in assertionsByProcess.allValues {
      for assertion in assertions {
        let type = assertion[kIOPMAssertionTypeKey] as? String
        let level = (assertion[kIOPMAssertionLevelKey] as? NSNumber)?.intValue ?? 0
        guard
          level != 0,
          type == kIOPMAssertionTypePreventUserIdleDisplaySleep
            || type == "NoDisplaySleepAssertion"
        else {
          continue
        }
        let owner = assertion["Process Name"] as? String ?? "Media application"
        if owner != "Clarity" { owners.append(owner) }
      }
    }
    return Array(Set(owners)).sorted()
  }

  private static func isLikelyGame(
    bundleIdentifier: String,
    isFullscreen: Bool
  ) -> Bool {
    guard isFullscreen else { return false }
    let identifier = bundleIdentifier.lowercased()
    let knownMarkers = [
      "steam", "epicgames", "blizzard", "battle.net", "riotgames", "minecraft", "roblox",
      "unity", "unreal", "wine", "crossover", "apple.chess",
    ]
    return knownMarkers.contains(where: identifier.contains) || !GCController.controllers().isEmpty
  }

  private static func frontmostWindowTitle(processIdentifier: pid_t) -> String? {
    guard AXIsProcessTrusted() else { return nil }
    let application = AXUIElementCreateApplication(processIdentifier)
    var windowValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
        "AXFocusedWindow" as CFString,
        &windowValue
      ) == .success,
      let windowValue
    else {
      return nil
    }
    let window = unsafeDowncast(windowValue, to: AXUIElement.self)
    var titleValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &titleValue) == .success
    else {
      return nil
    }
    return titleValue as? String
  }

  private static func isLikelyVideoTitle(_ title: String?, isFullscreen: Bool) -> Bool {
    guard isFullscreen, let title = title?.lowercased() else { return false }
    let markers = [
      "youtube", "netflix", "hulu", "disney+", "prime video", "vimeo", "twitch",
      "apple tv", "plex",
    ]
    return markers.contains(where: title.contains)
  }

  private static func activeScreenSharingApplications(canInspectWindows: Bool) -> [String] {
    let markers = [
      "obsproject", "screenflow", "camtasia", "loom", "screenstudio", "cleanshot", "kap",
      "screencast", "screensharing",
    ]
    let running: [String] = NSWorkspace.shared.runningApplications.compactMap { application in
      let identifier = application.bundleIdentifier?.lowercased() ?? ""
      guard markers.contains(where: identifier.contains) else { return nil }
      return application.localizedName ?? identifier
    }
    guard canInspectWindows else { return running }

    let windowOwners =
      (CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        CGWindowID(kCGNullWindowID)
      ) as? [[String: Any]])?.compactMap { window in
        window[kCGWindowOwnerName as String] as? String
      } ?? []
    let visible = windowOwners.filter { owner in
      let normalized = owner.lowercased()
      return markers.contains(where: normalized.contains)
    }
    return Array(Set(running + visible)).sorted()
  }
}
