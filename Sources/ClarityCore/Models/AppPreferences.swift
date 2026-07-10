public enum ControlMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case manual
  case automatic

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .manual: "Manual"
    case .automatic: "Automatic"
    }
  }
}

public struct AppPreferences: Codable, Equatable, Sendable {
  public var isEnabled: Bool
  public var isPaused: Bool
  public var controlMode: ControlMode
  public var selectedProfile: ClarityProfile
  public var schedule: ClockSchedule
  public var automaticScheduleKind: AutomaticScheduleKind
  public var solarSchedule: SolarSchedule
  public var solarLocation: SolarLocationSettings
  public var displaySettings: [String: DisplaySettings]
  public var activeAppRules: [ActiveAppRule]
  public var pauseInFullscreen: Bool
  public var hideFromAppSwitcher: Bool

  public init(
    isEnabled: Bool,
    isPaused: Bool,
    controlMode: ControlMode,
    selectedProfile: ClarityProfile,
    schedule: ClockSchedule,
    automaticScheduleKind: AutomaticScheduleKind = .clock,
    solarSchedule: SolarSchedule = .standard,
    solarLocation: SolarLocationSettings = .standard,
    displaySettings: [String: DisplaySettings] = [:],
    activeAppRules: [ActiveAppRule] = [],
    pauseInFullscreen: Bool = false,
    hideFromAppSwitcher: Bool = false
  ) {
    self.isEnabled = isEnabled
    self.isPaused = isPaused
    self.controlMode = controlMode
    self.selectedProfile = selectedProfile
    self.schedule = schedule
    self.automaticScheduleKind = automaticScheduleKind
    self.solarSchedule = solarSchedule
    self.solarLocation = solarLocation
    self.displaySettings = displaySettings
    self.activeAppRules = activeAppRules
    self.pauseInFullscreen = pauseInFullscreen
    self.hideFromAppSwitcher = hideFromAppSwitcher
  }

  public static let standard = AppPreferences(
    isEnabled: false,
    isPaused: false,
    controlMode: .automatic,
    selectedProfile: .health,
    schedule: .standard,
    automaticScheduleKind: .solar,
    solarSchedule: .health
  )

  private enum CodingKeys: String, CodingKey {
    case isEnabled
    case isPaused
    case controlMode
    case selectedProfile
    case schedule
    case automaticScheduleKind
    case solarSchedule
    case solarLocation
    case displaySettings
    case activeAppRules
    case pauseInFullscreen
    case hideFromAppSwitcher
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    isPaused = try container.decode(Bool.self, forKey: .isPaused)
    controlMode = try container.decode(ControlMode.self, forKey: .controlMode)
    selectedProfile = try container.decode(ClarityProfile.self, forKey: .selectedProfile)
    schedule = try container.decode(ClockSchedule.self, forKey: .schedule)
    automaticScheduleKind =
      try container.decodeIfPresent(AutomaticScheduleKind.self, forKey: .automaticScheduleKind)
      ?? .clock
    solarSchedule =
      try container.decodeIfPresent(SolarSchedule.self, forKey: .solarSchedule) ?? .standard
    solarLocation =
      try container.decodeIfPresent(SolarLocationSettings.self, forKey: .solarLocation) ?? .standard
    displaySettings =
      try container.decodeIfPresent([String: DisplaySettings].self, forKey: .displaySettings) ?? [:]
    activeAppRules =
      try container.decodeIfPresent([ActiveAppRule].self, forKey: .activeAppRules) ?? []
    pauseInFullscreen =
      try container.decodeIfPresent(Bool.self, forKey: .pauseInFullscreen) ?? false
    hideFromAppSwitcher =
      try container.decodeIfPresent(Bool.self, forKey: .hideFromAppSwitcher) ?? false
  }
}
