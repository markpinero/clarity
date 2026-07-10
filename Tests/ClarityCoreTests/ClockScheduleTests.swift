import XCTest

@testable import ClarityCore

final class ClockScheduleTests: XCTestCase {
  func testNightTransitionInterpolatesBetweenDayAndNightProfiles() {
    let schedule = ClockSchedule(
      dayStartMinute: 7 * 60,
      nightStartMinute: 20 * 60,
      transitionMinutes: 60,
      dayProfile: .health,
      nightProfile: .evening
    )

    let result = schedule.resolve(atMinute: 20 * 60 + 30)

    XCTAssertEqual(result.adjustment.kelvin, 4_200)
    XCTAssertEqual(result.adjustment.brightness, 0.9, accuracy: 0.001)
    XCTAssertEqual(result.phase, .transitionToNight(progress: 0.5))
  }

  func testScheduleWrapsAcrossMidnightAndTransitionsBackToDay() {
    let schedule = ClockSchedule(
      dayStartMinute: 7 * 60,
      nightStartMinute: 20 * 60,
      transitionMinutes: 60,
      dayProfile: .health,
      nightProfile: .evening
    )

    XCTAssertEqual(schedule.resolve(atMinute: 2 * 60).phase, .night)
    XCTAssertEqual(schedule.resolve(atMinute: 12 * 60).phase, .day)

    let morningMidpoint = schedule.resolve(atMinute: 7 * 60 + 30)
    XCTAssertEqual(morningMidpoint.adjustment.kelvin, 4_200)
    XCTAssertEqual(morningMidpoint.adjustment.brightness, 0.9, accuracy: 0.001)
    XCTAssertEqual(morningMidpoint.phase, .transitionToDay(progress: 0.5))
  }

  func testScheduleNormalizesInputsAndClampsTransitionDuration() {
    let schedule = ClockSchedule(
      dayStartMinute: -60,
      nightStartMinute: 1_500,
      transitionMinutes: 900,
      dayProfile: .health,
      nightProfile: .sleep
    )

    XCTAssertEqual(schedule.dayStartMinute, 23 * 60)
    XCTAssertEqual(schedule.nightStartMinute, 60)
    XCTAssertEqual(schedule.transitionMinutes, 240)
    XCTAssertEqual(schedule.resolve(atMinute: -30), schedule.resolve(atMinute: 1_410))
  }
}
