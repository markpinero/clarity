import Foundation

public enum AutomaticScheduleKind: String, CaseIterable, Codable, Identifiable, Sendable {
  case clock
  case solar

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .clock: "Clock"
    case .solar: "Sunrise & Sunset"
    }
  }
}

public struct SolarSchedule: Codable, Equatable, Sendable {
  public let transitionMinutes: Int
  public let dayProfile: ClarityProfile
  public let nightProfile: ClarityProfile
  public let sleepProfile: ClarityProfile
  public let usesSleepAdjustment: Bool
  public let bedtimeMinute: Int
  public let wakeMinute: Int
  public let dayTransitionMinutes: Int
  public let nightTransitionMinutes: Int
  public let sleepTransitionMinutes: Int
  public let newMoonOffsetSeconds: Int
  public let fullMoonOffsetSeconds: Int

  public init(
    transitionMinutes: Int,
    dayProfile: ClarityProfile,
    nightProfile: ClarityProfile,
    sleepProfile: ClarityProfile = .sleep,
    usesSleepAdjustment: Bool = false,
    bedtimeMinute: Int = 0,
    wakeMinute: Int = 4 * 60,
    dayTransitionMinutes: Int? = nil,
    nightTransitionMinutes: Int? = nil,
    sleepTransitionMinutes: Int? = nil,
    newMoonOffsetSeconds: Int = 0,
    fullMoonOffsetSeconds: Int = 0
  ) {
    let sharedTransition = Self.clampedTransition(transitionMinutes)
    self.transitionMinutes = sharedTransition
    self.dayProfile = dayProfile
    self.nightProfile = nightProfile
    self.sleepProfile = sleepProfile
    self.usesSleepAdjustment = usesSleepAdjustment
    self.bedtimeMinute = Self.normalizedMinute(bedtimeMinute)
    self.wakeMinute = Self.normalizedMinute(wakeMinute)
    self.dayTransitionMinutes = Self.clampedTransition(dayTransitionMinutes ?? sharedTransition)
    self.nightTransitionMinutes = Self.clampedTransition(nightTransitionMinutes ?? sharedTransition)
    self.sleepTransitionMinutes = Self.clampedTransition(sleepTransitionMinutes ?? sharedTransition)
    self.newMoonOffsetSeconds = max(0, newMoonOffsetSeconds)
    self.fullMoonOffsetSeconds = max(0, fullMoonOffsetSeconds)
  }

  public static let health = SolarSchedule(
    transitionMinutes: 60,
    dayProfile: .health,
    nightProfile: .evening,
    sleepProfile: .sleep,
    usesSleepAdjustment: true,
    bedtimeMinute: 0,
    wakeMinute: 4 * 60,
    newMoonOffsetSeconds: 300,
    fullMoonOffsetSeconds: 1_200
  )

  public static let standard = health

  public func resolve(
    atMinute minute: Double,
    sunriseMinute: Double,
    sunsetMinute: Double,
    moonPhase: Double = 0
  ) -> ScheduledAdjustment {
    let currentSecond = Self.normalizedSecond(minute * 60)
    let clampedMoonPhase = min(max(moonPhase, 0), 1)
    let moonOffset =
      (1 - clampedMoonPhase) * Double(newMoonOffsetSeconds)
      + clampedMoonPhase * Double(fullMoonOffsetSeconds)
    let sunriseSecond = Self.normalizedSecond(sunriseMinute * 60 - moonOffset)
    let sunsetSecond = Self.normalizedSecond(sunsetMinute * 60 - moonOffset)

    let base = resolveDayAndNight(
      atSecond: currentSecond,
      sunriseSecond: sunriseSecond,
      sunsetSecond: sunsetSecond
    )

    guard usesSleepAdjustment else { return base }
    let sleep = sleepProgress(atSecond: currentSecond)
    guard sleep.factor > 0 else { return base }

    return ScheduledAdjustment(
      adjustment: .interpolated(
        from: base.adjustment,
        to: sleepProfile.adjustment,
        progress: sleep.factor
      ),
      phase: sleep.phase
    )
  }

  private func resolveDayAndNight(
    atSecond currentSecond: Double,
    sunriseSecond: Double,
    sunsetSecond: Double
  ) -> ScheduledAdjustment {
    let dayDuration = Double(dayTransitionMinutes * 60)
    let nightDuration = Double(nightTransitionMinutes * 60)
    let dayStart = Self.normalizedSecond(sunriseSecond - dayDuration / 2)
    let nightStart = Self.normalizedSecond(sunsetSecond - nightDuration / 2)

    if let progress = Self.progress(
      atSecond: currentSecond,
      fromSecond: dayStart,
      duration: dayDuration
    ) {
      return ScheduledAdjustment(
        adjustment: .interpolated(
          from: nightProfile.adjustment,
          to: dayProfile.adjustment,
          progress: progress
        ),
        phase: .transitionToDay(progress: progress)
      )
    }

    if let progress = Self.progress(
      atSecond: currentSecond,
      fromSecond: nightStart,
      duration: nightDuration
    ) {
      return ScheduledAdjustment(
        adjustment: .interpolated(
          from: dayProfile.adjustment,
          to: nightProfile.adjustment,
          progress: progress
        ),
        phase: .transitionToNight(progress: progress)
      )
    }

    let dayStableStart = Self.normalizedSecond(dayStart + dayDuration)
    if Self.contains(
      currentSecond,
      fromSecond: dayStableStart,
      toSecond: nightStart
    ) {
      return ScheduledAdjustment(adjustment: dayProfile.adjustment, phase: .day)
    }
    return ScheduledAdjustment(adjustment: nightProfile.adjustment, phase: .night)
  }

  private func sleepProgress(atSecond currentSecond: Double) -> (
    factor: Double, phase: SchedulePhase
  ) {
    let duration = Double(sleepTransitionMinutes * 60)
    let bedtimeSecond = Double(bedtimeMinute * 60)
    let wakeSecond = Double(wakeMinute * 60)
    let bedtimeStart = Self.normalizedSecond(bedtimeSecond - duration)
    let wakeStart = Self.normalizedSecond(wakeSecond - duration)

    if let progress = Self.progress(
      atSecond: currentSecond,
      fromSecond: bedtimeStart,
      duration: duration
    ) {
      return (progress, .transitionToSleep(progress: progress))
    }
    if Self.contains(currentSecond, fromSecond: bedtimeSecond, toSecond: wakeStart) {
      return (1, .sleep)
    }
    if let progress = Self.progress(
      atSecond: currentSecond,
      fromSecond: wakeStart,
      duration: duration
    ) {
      return (1 - progress, .transitionFromSleep(progress: progress))
    }
    return (0, .night)
  }

  private static func progress(
    atSecond current: Double,
    fromSecond start: Double,
    duration: Double
  ) -> Double? {
    let elapsed = normalizedSecond(current - start)
    guard elapsed <= duration else { return nil }
    return min(max(elapsed / duration, 0), 1)
  }

  private static func contains(
    _ current: Double,
    fromSecond start: Double,
    toSecond end: Double
  ) -> Bool {
    normalizedSecond(current - start) < normalizedSecond(end - start)
  }

  private static func normalizedMinute(_ minute: Int) -> Int {
    ((minute % 1_440) + 1_440) % 1_440
  }

  private static func normalizedSecond(_ second: Double) -> Double {
    let result = second.truncatingRemainder(dividingBy: 86_400)
    return result >= 0 ? result : result + 86_400
  }

  private static func clampedTransition(_ minutes: Int) -> Int {
    max(1, min(minutes, 240))
  }

  private enum CodingKeys: String, CodingKey {
    case transitionMinutes
    case dayProfile
    case nightProfile
    case sleepProfile
    case usesSleepAdjustment
    case bedtimeMinute
    case wakeMinute
    case dayTransitionMinutes
    case nightTransitionMinutes
    case sleepTransitionMinutes
    case newMoonOffsetSeconds
    case fullMoonOffsetSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let transitionMinutes = try container.decode(Int.self, forKey: .transitionMinutes)
    self.init(
      transitionMinutes: transitionMinutes,
      dayProfile: try container.decode(ClarityProfile.self, forKey: .dayProfile),
      nightProfile: try container.decode(ClarityProfile.self, forKey: .nightProfile),
      sleepProfile: try container.decodeIfPresent(ClarityProfile.self, forKey: .sleepProfile)
        ?? .sleep,
      usesSleepAdjustment: try container.decodeIfPresent(Bool.self, forKey: .usesSleepAdjustment)
        ?? false,
      bedtimeMinute: try container.decodeIfPresent(Int.self, forKey: .bedtimeMinute) ?? 0,
      wakeMinute: try container.decodeIfPresent(Int.self, forKey: .wakeMinute) ?? 4 * 60,
      dayTransitionMinutes: try container.decodeIfPresent(
        Int.self,
        forKey: .dayTransitionMinutes
      ),
      nightTransitionMinutes: try container.decodeIfPresent(
        Int.self,
        forKey: .nightTransitionMinutes
      ),
      sleepTransitionMinutes: try container.decodeIfPresent(
        Int.self,
        forKey: .sleepTransitionMinutes
      ),
      newMoonOffsetSeconds: try container.decodeIfPresent(
        Int.self,
        forKey: .newMoonOffsetSeconds
      ) ?? 0,
      fullMoonOffsetSeconds: try container.decodeIfPresent(
        Int.self,
        forKey: .fullMoonOffsetSeconds
      ) ?? 0
    )
  }
}

public struct SolarEvents: Codable, Equatable, Sendable {
  public let sunriseMinute: Double
  public let sunsetMinute: Double

  public init(sunriseMinute: Double, sunsetMinute: Double) {
    self.sunriseMinute = Self.normalizedMinute(sunriseMinute)
    self.sunsetMinute = Self.normalizedMinute(sunsetMinute)
  }

  private static func normalizedMinute(_ minute: Double) -> Double {
    let result = minute.truncatingRemainder(dividingBy: 1_440)
    return result >= 0 ? result : result + 1_440
  }
}

public enum SolarCalculator {
  public static func events(
    on date: Date,
    coordinate: GeographicCoordinate,
    calendar: Calendar = .current
  ) -> SolarEvents? {
    let radians = Double.pi / 180
    let longitude = -coordinate.longitude * radians
    let latitude = coordinate.latitude * radians
    let milliseconds = date.timeIntervalSince1970 * 1_000
    let wholeDays = Double(Int64(milliseconds) / 86_400_000)
    let days = wholeDays - 0.5 + 2_440_588 - 2_451_545
    let cycle = (days - 0.0009 - longitude / (2 * Double.pi)).rounded()
    let approximateTransit = 0.0009 + longitude / (2 * Double.pi) + cycle
    let meanAnomaly = radians * (357.5291 + 0.985_600_28 * approximateTransit)
    let center =
      radians
      * (1.9148 * sin(meanAnomaly) + 0.02 * sin(2 * meanAnomaly)
        + 0.0003 * sin(3 * meanAnomaly))
    let eclipticLongitude = meanAnomaly + center + radians * 102.9372 + Double.pi
    let declination = asin(sin(eclipticLongitude) * sin(radians * 23.4397))
    let solarNoon =
      2_451_545 + approximateTransit + 0.0053 * sin(meanAnomaly)
      - 0.0069 * sin(2 * eclipticLongitude)
    let cosineHourAngle =
      (sin(-0.833 * radians) - sin(latitude) * sin(declination))
      / (cos(latitude) * cos(declination))
    guard (-1...1).contains(cosineHourAngle) else { return nil }

    let hourAngle = acos(cosineHourAngle)
    let sunsetTransit = 0.0009 + (hourAngle + longitude) / (2 * Double.pi) + cycle
    let sunset =
      2_451_545 + sunsetTransit + 0.0053 * sin(meanAnomaly)
      - 0.0069 * sin(2 * eclipticLongitude)
    let sunrise = solarNoon - (sunset - solarNoon)

    return SolarEvents(
      sunriseMinute: minuteOfDay(forJulianDate: sunrise, calendar: calendar),
      sunsetMinute: minuteOfDay(forJulianDate: sunset, calendar: calendar)
    )
  }

  private static func minuteOfDay(forJulianDate julianDate: Double, calendar: Calendar) -> Double {
    let milliseconds = Int64(
      ((julianDate + 0.5 - 2_440_588) * 86_400_000).rounded(.towardZero)
    )
    let event = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: event)
    return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
      + Double(components.second ?? 0) / 60
      + Double(components.nanosecond ?? 0) / 60_000_000_000
  }
}

public enum MoonCalculator {
  public static func illuminatedFraction(at date: Date) -> Double {
    let radians = Double.pi / 180
    let day = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_444_238.5
    let meanLongitude = fixedAngle(0.985_647_332_099_083_7 * day)
    let meanAnomaly = fixedAngle(meanLongitude - 3.762_863)
    var eccentricAnomaly = meanAnomaly * radians

    while true {
      let delta =
        eccentricAnomaly - 0.016_718 * sin(eccentricAnomaly) - meanAnomaly * radians
      eccentricAnomaly -= delta / (1 - 0.016_718 * cos(eccentricAnomaly))
      if abs(delta) <= 0.000_001 { break }
    }

    let eccentricLongitude =
      2
      * atan(
        sqrt((1 + 0.016_718) / (1 - 0.016_718)) * tan(eccentricAnomaly / 2)
      ) / radians
    let sunLongitude = fixedAngle(eccentricLongitude + 282.596_403)
    let moonLongitude = fixedAngle(13.176_396_6 * day + 64.975_464)
    let moonAnomaly = fixedAngle(moonLongitude - 0.111_404_1 * day - 349.383_063)
    let evection =
      1.2739 * sin(radians * (2 * (moonLongitude - sunLongitude) - moonAnomaly))
    let annualEquation = 0.1858 * sin(radians * meanAnomaly)
    let correction = 0.37 * sin(radians * meanAnomaly)
    let correctedAnomaly = moonAnomaly + evection - annualEquation - correction
    let equationOfCenter = 6.2886 * sin(radians * correctedAnomaly)
    let fourthCorrection = 0.214 * sin(radians * 2 * correctedAnomaly)
    let correctedLongitude =
      moonLongitude + evection + equationOfCenter - annualEquation + fourthCorrection
    let variation = 0.6583 * sin(radians * 2 * (correctedLongitude - sunLongitude))
    let moonAge = correctedLongitude + variation - sunLongitude
    return min(max((1 - cos(radians * moonAge)) / 2, 0), 1)
  }

  private static func fixedAngle(_ angle: Double) -> Double {
    angle - 360 * floor(angle / 360)
  }
}

public struct SchedulePreview: Equatable, Sendable {
  public struct Sample: Equatable, Sendable {
    public let minute: Int
    public let adjustment: DisplayAdjustment

    public init(minute: Int, adjustment: DisplayAdjustment) {
      self.minute = minute
      self.adjustment = adjustment
    }
  }

  public let samples: [Sample]
  public let dayStartMinute: Double
  public let nightStartMinute: Double

  public init(samples: [Sample], dayStartMinute: Double, nightStartMinute: Double) {
    self.samples = samples
    self.dayStartMinute = dayStartMinute
    self.nightStartMinute = nightStartMinute
  }

  public static func clock(
    schedule: ClockSchedule,
    sampleIntervalMinutes: Int = 30
  ) -> SchedulePreview {
    make(
      dayStartMinute: Double(schedule.dayStartMinute),
      nightStartMinute: Double(schedule.nightStartMinute),
      sampleIntervalMinutes: sampleIntervalMinutes
    ) { minute in
      schedule.resolve(atMinute: minute).adjustment
    }
  }

  public static func solar(
    schedule: SolarSchedule,
    sunriseMinute: Double,
    sunsetMinute: Double,
    moonPhase: Double = 0,
    sampleIntervalMinutes: Int = 30
  ) -> SchedulePreview {
    make(
      dayStartMinute: sunriseMinute,
      nightStartMinute: sunsetMinute,
      sampleIntervalMinutes: sampleIntervalMinutes
    ) { minute in
      schedule.resolve(
        atMinute: minute,
        sunriseMinute: sunriseMinute,
        sunsetMinute: sunsetMinute,
        moonPhase: moonPhase
      ).adjustment
    }
  }

  private static func make(
    dayStartMinute: Double,
    nightStartMinute: Double,
    sampleIntervalMinutes: Int,
    adjustment: (Double) -> DisplayAdjustment
  ) -> SchedulePreview {
    let interval = max(1, sampleIntervalMinutes)
    var minutes = Array(stride(from: 0, through: 1_440, by: interval))
    if minutes.last != 1_440 {
      minutes.append(1_440)
    }
    return SchedulePreview(
      samples: minutes.map { Sample(minute: $0, adjustment: adjustment(Double($0))) },
      dayStartMinute: dayStartMinute,
      nightStartMinute: nightStartMinute
    )
  }
}
