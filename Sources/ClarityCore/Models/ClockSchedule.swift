public struct ClockSchedule: Codable, Equatable, Sendable {
  public let dayStartMinute: Int
  public let nightStartMinute: Int
  public let transitionMinutes: Int
  public let dayProfile: ClarityProfile
  public let nightProfile: ClarityProfile

  public init(
    dayStartMinute: Int,
    nightStartMinute: Int,
    transitionMinutes: Int,
    dayProfile: ClarityProfile,
    nightProfile: ClarityProfile
  ) {
    self.dayStartMinute = Self.normalizedMinute(dayStartMinute)
    self.nightStartMinute = Self.normalizedMinute(nightStartMinute)
    self.transitionMinutes = max(1, min(transitionMinutes, 240))
    self.dayProfile = dayProfile
    self.nightProfile = nightProfile
  }

  public static let standard = ClockSchedule(
    dayStartMinute: 7 * 60,
    nightStartMinute: 20 * 60,
    transitionMinutes: 60,
    dayProfile: .health,
    nightProfile: .evening
  )

  public func resolve(atMinute minute: Double) -> ScheduledAdjustment {
    let currentMinute = Self.normalizedMinute(minute)
    let elapsedFromDay = Self.elapsed(since: Double(dayStartMinute), at: currentMinute)
    let elapsedFromNight = Self.elapsed(since: Double(nightStartMinute), at: currentMinute)
    let duration = Double(transitionMinutes)

    if elapsedFromDay <= elapsedFromNight {
      guard elapsedFromDay < duration else {
        return ScheduledAdjustment(adjustment: dayProfile.adjustment, phase: .day)
      }

      let progress = elapsedFromDay / duration
      return ScheduledAdjustment(
        adjustment: .interpolated(
          from: nightProfile.adjustment,
          to: dayProfile.adjustment,
          progress: progress
        ),
        phase: .transitionToDay(progress: progress)
      )
    }

    guard elapsedFromNight < duration else {
      return ScheduledAdjustment(adjustment: nightProfile.adjustment, phase: .night)
    }

    let progress = elapsedFromNight / duration
    return ScheduledAdjustment(
      adjustment: .interpolated(
        from: dayProfile.adjustment,
        to: nightProfile.adjustment,
        progress: progress
      ),
      phase: .transitionToNight(progress: progress)
    )
  }

  private static func normalizedMinute(_ minute: Int) -> Int {
    ((minute % 1_440) + 1_440) % 1_440
  }

  private static func normalizedMinute(_ minute: Double) -> Double {
    let result = minute.truncatingRemainder(dividingBy: 1_440)
    return result >= 0 ? result : result + 1_440
  }

  private static func elapsed(since start: Double, at current: Double) -> Double {
    normalizedMinute(current - start)
  }
}

public struct ScheduledAdjustment: Equatable, Sendable {
  public let adjustment: DisplayAdjustment
  public let phase: SchedulePhase

  public init(adjustment: DisplayAdjustment, phase: SchedulePhase) {
    self.adjustment = adjustment
    self.phase = phase
  }
}

public enum SchedulePhase: Equatable, Sendable {
  case day
  case transitionToNight(progress: Double)
  case night
  case transitionToDay(progress: Double)
  case transitionToSleep(progress: Double)
  case sleep
  case transitionFromSleep(progress: Double)
}
