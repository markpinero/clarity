import Foundation

public enum BreakPhase: String, Codable, Equatable, Sendable {
  case stopped
  case focusing
  case countdown
  case breaking
  case paused
}

public enum BreakKind: String, Codable, Equatable, Sendable {
  case short
  case long
}

public enum BreakPauseReason: String, CaseIterable, Codable, Hashable, Sendable {
  case manual
  case idle
  case calendarMeeting
  case call
  case videoPlayback
  case gaming
  case screenSharing

  public var name: String {
    switch self {
    case .manual: "Manual pause"
    case .idle: "Natural break"
    case .calendarMeeting: "Calendar meeting"
    case .call: "Meeting or call"
    case .videoPlayback: "Video playback"
    case .gaming: "Gaming"
    case .screenSharing: "Screen recording or sharing"
    }
  }
}

public struct BreakSnapshot: Codable, Equatable, Sendable {
  public var phase: BreakPhase
  public var phaseDeadline: Date?
  public var pausedPhase: BreakPhase?
  public var pausedRemaining: TimeInterval?
  public var breakKind: BreakKind?
  public var completedFocusIntervals: Int
  public var snoozeCount: Int
  public var pauseReasons: Set<BreakPauseReason>

  public init(
    phase: BreakPhase,
    phaseDeadline: Date? = nil,
    pausedPhase: BreakPhase? = nil,
    pausedRemaining: TimeInterval? = nil,
    breakKind: BreakKind? = nil,
    completedFocusIntervals: Int = 0,
    snoozeCount: Int = 0,
    pauseReasons: Set<BreakPauseReason> = []
  ) {
    self.phase = phase
    self.phaseDeadline = phaseDeadline
    self.pausedPhase = pausedPhase
    self.pausedRemaining = pausedRemaining
    self.breakKind = breakKind
    self.completedFocusIntervals = max(0, completedFocusIntervals)
    self.snoozeCount = max(0, snoozeCount)
    self.pauseReasons = pauseReasons
  }

  public static let stopped = BreakSnapshot(phase: .stopped)

  public func remaining(at date: Date) -> TimeInterval? {
    if phase == .paused { return pausedRemaining }
    return phaseDeadline.map { max(0, $0.timeIntervalSince(date)) }
  }

  private enum CodingKeys: String, CodingKey {
    case phase
    case phaseDeadline
    case pausedPhase
    case pausedRemaining
    case breakKind
    case completedFocusIntervals
    case snoozeCount
    case pauseReasons
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      phase: try container.decode(BreakPhase.self, forKey: .phase),
      phaseDeadline: try container.decodeIfPresent(Date.self, forKey: .phaseDeadline),
      pausedPhase: try container.decodeIfPresent(BreakPhase.self, forKey: .pausedPhase),
      pausedRemaining: try container.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining),
      breakKind: try container.decodeIfPresent(BreakKind.self, forKey: .breakKind),
      completedFocusIntervals: try container.decodeIfPresent(
        Int.self,
        forKey: .completedFocusIntervals
      ) ?? 0,
      snoozeCount: try container.decodeIfPresent(Int.self, forKey: .snoozeCount) ?? 0,
      pauseReasons: try container.decodeIfPresent(
        Set<BreakPauseReason>.self,
        forKey: .pauseReasons
      ) ?? []
    )
  }
}
