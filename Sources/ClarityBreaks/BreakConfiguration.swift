import Foundation

public struct BreakConfiguration: Codable, Equatable, Sendable {
  public static let preBreakNotificationDuration: TimeInterval = 10

  public var focusDuration: TimeInterval
  public var shortBreakDuration: TimeInterval
  public var longBreakDuration: TimeInterval
  public var longBreakEvery: Int
  public var countdownDuration: TimeInterval
  public var snoozeDuration: TimeInterval
  public var idleResetEnabled: Bool
  public var idleResetDuration: TimeInterval
  public var pauseDuringCalendarMeetings: Bool
  public var pauseDuringCalls: Bool
  public var pauseDuringVideoPlayback: Bool
  public var pauseDuringGaming: Bool
  public var pauseDuringScreenSharing: Bool

  public init(
    focusDuration: TimeInterval,
    shortBreakDuration: TimeInterval,
    longBreakDuration: TimeInterval,
    longBreakEvery: Int,
    countdownDuration: TimeInterval,
    snoozeDuration: TimeInterval,
    idleResetEnabled: Bool = true,
    idleResetDuration: TimeInterval = 5 * 60,
    pauseDuringCalendarMeetings: Bool = true,
    pauseDuringCalls: Bool = true,
    pauseDuringVideoPlayback: Bool = true,
    pauseDuringGaming: Bool = true,
    pauseDuringScreenSharing: Bool = true
  ) {
    self.focusDuration = max(1, focusDuration)
    self.shortBreakDuration = max(1, shortBreakDuration)
    self.longBreakDuration = max(1, longBreakDuration)
    self.longBreakEvery = max(1, longBreakEvery)
    self.countdownDuration = min(Self.preBreakNotificationDuration, self.focusDuration)
    self.snoozeDuration = max(1, snoozeDuration)
    self.idleResetEnabled = idleResetEnabled
    self.idleResetDuration = max(30, idleResetDuration)
    self.pauseDuringCalendarMeetings = pauseDuringCalendarMeetings
    self.pauseDuringCalls = pauseDuringCalls
    self.pauseDuringVideoPlayback = pauseDuringVideoPlayback
    self.pauseDuringGaming = pauseDuringGaming
    self.pauseDuringScreenSharing = pauseDuringScreenSharing
  }

  public static let standard = BreakConfiguration(
    focusDuration: 20 * 60,
    shortBreakDuration: 20,
    longBreakDuration: 5 * 60,
    longBreakEvery: 4,
    countdownDuration: 10,
    snoozeDuration: 3 * 60
  )

  private enum CodingKeys: String, CodingKey {
    case focusDuration
    case shortBreakDuration
    case longBreakDuration
    case longBreakEvery
    case countdownDuration
    case snoozeDuration
    case idleResetEnabled
    case idleResetDuration
    case pauseDuringCalendarMeetings
    case pauseDuringCalls
    case pauseDuringVideoPlayback
    case pauseDuringGaming
    case pauseDuringScreenSharing
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      focusDuration: try container.decode(TimeInterval.self, forKey: .focusDuration),
      shortBreakDuration: try container.decode(TimeInterval.self, forKey: .shortBreakDuration),
      longBreakDuration: try container.decode(TimeInterval.self, forKey: .longBreakDuration),
      longBreakEvery: try container.decode(Int.self, forKey: .longBreakEvery),
      countdownDuration: try container.decode(TimeInterval.self, forKey: .countdownDuration),
      snoozeDuration: try container.decode(TimeInterval.self, forKey: .snoozeDuration),
      idleResetEnabled: try container.decodeIfPresent(Bool.self, forKey: .idleResetEnabled) ?? true,
      idleResetDuration: try container.decodeIfPresent(
        TimeInterval.self,
        forKey: .idleResetDuration
      ) ?? 5 * 60,
      pauseDuringCalendarMeetings: try container.decodeIfPresent(
        Bool.self,
        forKey: .pauseDuringCalendarMeetings
      ) ?? true,
      pauseDuringCalls: try container.decodeIfPresent(Bool.self, forKey: .pauseDuringCalls) ?? true,
      pauseDuringVideoPlayback: try container.decodeIfPresent(
        Bool.self,
        forKey: .pauseDuringVideoPlayback
      ) ?? true,
      pauseDuringGaming: try container.decodeIfPresent(
        Bool.self,
        forKey: .pauseDuringGaming
      ) ?? true,
      pauseDuringScreenSharing: try container.decodeIfPresent(
        Bool.self,
        forKey: .pauseDuringScreenSharing
      ) ?? true
    )
  }
}
