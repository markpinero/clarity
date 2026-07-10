import AppKit

@MainActor
final class ActiveApplicationMonitor {
  struct State: Equatable, Sendable {
    let bundleIdentifier: String?
    let displayName: String
    let processIdentifier: pid_t?

    static let unavailable = State(
      bundleIdentifier: nil,
      displayName: "Unavailable",
      processIdentifier: nil
    )
  }

  var onChange: ((State) -> Void)?
  private var observer: NSObjectProtocol?

  func start() {
    guard observer == nil else { return }
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let application =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let state = Self.state(for: application)
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.onChange?(state)
      }
    }
    onChange?(Self.state(for: NSWorkspace.shared.frontmostApplication))
  }

  func stop() {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observer = nil
  }

  nonisolated private static func state(for application: NSRunningApplication?) -> State {
    guard let application else { return .unavailable }
    return State(
      bundleIdentifier: application.bundleIdentifier,
      displayName: application.localizedName ?? application.bundleIdentifier ?? "Unknown App",
      processIdentifier: application.processIdentifier
    )
  }
}
