import Foundation

public struct BreakContextObservation: Equatable, Sendable {
  public var idleDuration: TimeInterval
  public var hasCalendarMeeting: Bool
  public var hasActiveCall: Bool
  public var hasVideoPlayback: Bool
  public var hasActiveGame: Bool
  public var isScreenSharing: Bool

  public init(
    idleDuration: TimeInterval = 0,
    hasCalendarMeeting: Bool = false,
    hasActiveCall: Bool = false,
    hasVideoPlayback: Bool = false,
    hasActiveGame: Bool = false,
    isScreenSharing: Bool = false
  ) {
    self.idleDuration = max(0, idleDuration)
    self.hasCalendarMeeting = hasCalendarMeeting
    self.hasActiveCall = hasActiveCall
    self.hasVideoPlayback = hasVideoPlayback
    self.hasActiveGame = hasActiveGame
    self.isScreenSharing = isScreenSharing
  }
}

public struct BreakContextResolution: Equatable, Sendable {
  public let reasons: Set<BreakPauseReason>
  public let resetFocusAfterIdle: Bool

  public init(reasons: Set<BreakPauseReason>, resetFocusAfterIdle: Bool) {
    self.reasons = reasons
    self.resetFocusAfterIdle = resetFocusAfterIdle
  }
}

public struct BreakContextResolver: Sendable {
  private var wasIdleResetQualified = false

  public init() {}

  public mutating func resolve(
    _ observation: BreakContextObservation,
    configuration: BreakConfiguration
  ) -> BreakContextResolution {
    var reasons: Set<BreakPauseReason> = []
    let idleResetQualified =
      configuration.idleResetEnabled
      && observation.idleDuration >= configuration.idleResetDuration

    if idleResetQualified { reasons.insert(.idle) }
    if configuration.pauseDuringCalendarMeetings, observation.hasCalendarMeeting {
      reasons.insert(.calendarMeeting)
    }
    if configuration.pauseDuringCalls, observation.hasActiveCall {
      reasons.insert(.call)
    }
    if configuration.pauseDuringVideoPlayback, observation.hasVideoPlayback {
      reasons.insert(.videoPlayback)
    }
    if configuration.pauseDuringGaming, observation.hasActiveGame {
      reasons.insert(.gaming)
    }
    if configuration.pauseDuringScreenSharing, observation.isScreenSharing {
      reasons.insert(.screenSharing)
    }

    let resetFocusAfterIdle = wasIdleResetQualified && !idleResetQualified
    wasIdleResetQualified = idleResetQualified
    return BreakContextResolution(
      reasons: reasons,
      resetFocusAfterIdle: resetFocusAfterIdle
    )
  }
}
