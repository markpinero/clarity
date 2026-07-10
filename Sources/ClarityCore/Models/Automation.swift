import Foundation

public struct AutomationContext: Equatable, Sendable {
  public var activeApplicationBundleIdentifier: String?
  public var isActiveApplicationFullscreen: Bool

  public init(
    activeApplicationBundleIdentifier: String? = nil,
    isActiveApplicationFullscreen: Bool = false
  ) {
    self.activeApplicationBundleIdentifier = activeApplicationBundleIdentifier
    self.isActiveApplicationFullscreen = isActiveApplicationFullscreen
  }

  public static let empty = AutomationContext()
}

public struct ActiveAppRule: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var bundleIdentifier: String
  public var displayName: String
  public var action: ActiveAppAction

  public init(
    id: UUID = UUID(),
    bundleIdentifier: String,
    displayName: String,
    action: ActiveAppAction
  ) {
    self.id = id
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.action = action
  }
}

public enum ActiveAppAction: Codable, Equatable, Hashable, Sendable {
  case pause
  case profile(ClarityProfile)

  public var name: String {
    switch self {
    case .pause: "Pause adjustments"
    case .profile(let profile): "Use \(profile.name)"
    }
  }
}

public enum AutomationPauseReason: Equatable, Sendable {
  case activeApplication(bundleIdentifier: String)
  case fullscreen
}
