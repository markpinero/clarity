public struct DisplaySettings: Codable, Equatable, Sendable {
  public var isEnabled: Bool
  public var profileOverride: ClarityProfile?

  public init(isEnabled: Bool = true, profileOverride: ClarityProfile? = nil) {
    self.isEnabled = isEnabled
    self.profileOverride = profileOverride
  }

  public static let standard = DisplaySettings()
}
