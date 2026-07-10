import Foundation
import XCTest

@testable import ClarityCore

final class SolarScheduleTests: XCTestCase {
  func testHealthIsTheSafeFirstRunDefault() {
    let preferences = AppPreferences.standard

    XCTAssertFalse(preferences.isEnabled)
    XCTAssertEqual(preferences.controlMode, .automatic)
    XCTAssertEqual(preferences.selectedProfile, .health)
    XCTAssertEqual(preferences.automaticScheduleKind, .solar)
    XCTAssertEqual(preferences.solarSchedule, .health)
    XCTAssertEqual(preferences.solarSchedule.dayProfile.adjustment.kelvin, 5_000)
    XCTAssertEqual(preferences.solarSchedule.dayProfile.adjustment.brightness, 1)
    XCTAssertEqual(preferences.solarSchedule.nightProfile.adjustment.kelvin, 3_400)
    XCTAssertEqual(preferences.solarSchedule.nightProfile.adjustment.brightness, 0.8)
    XCTAssertEqual(preferences.solarSchedule.sleepProfile.adjustment.kelvin, 2_700)
    XCTAssertEqual(preferences.solarSchedule.sleepProfile.adjustment.brightness, 0.75)
  }

  func testLegacyNeutralProfileDecodesAsHealth() throws {
    let decoded = try JSONDecoder().decode(ClarityProfile.self, from: Data("\"neutral\"".utf8))

    XCTAssertEqual(decoded, .health)
  }

  func testGreenwichEquinoxProducesExpectedSunriseAndSunset() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let date = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))
    )

    let events = try XCTUnwrap(
      SolarCalculator.events(
        on: date,
        coordinate: GeographicCoordinate(latitude: 51.4769, longitude: 0),
        calendar: calendar
      )
    )

    XCTAssertEqual(events.sunriseMinute, 6 * 60 + 3, accuracy: 15)
    XCTAssertEqual(events.sunsetMinute, 18 * 60 + 13, accuracy: 15)
  }

  func testSolarScheduleTransitionsFromNightAtSunriseAndDayAtSunset() {
    let schedule = SolarSchedule(
      transitionMinutes: 60,
      dayProfile: .health,
      nightProfile: .evening
    )

    let morning = schedule.resolve(
      atMinute: 6 * 60,
      sunriseMinute: 6 * 60,
      sunsetMinute: 18 * 60
    )
    let evening = schedule.resolve(
      atMinute: 18 * 60,
      sunriseMinute: 6 * 60,
      sunsetMinute: 18 * 60
    )

    XCTAssertEqual(morning.adjustment.kelvin, 4_200)
    XCTAssertEqual(morning.phase, .transitionToDay(progress: 0.5))
    XCTAssertEqual(evening.adjustment.kelvin, 4_200)
    XCTAssertEqual(evening.phase, .transitionToNight(progress: 0.5))
  }

  func testHealthScheduleMatchesCurrentLegacyIrisSolarAndSleepSamples() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let coordinate = GeographicCoordinate(
      latitude: 30.19280052185059,
      longitude: -118.3690032958984
    )
    let date = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 5, minute: 30))
    )
    let events = try XCTUnwrap(
      SolarCalculator.events(on: date, coordinate: coordinate, calendar: calendar)
    )
    let moonPhase = MoonCalculator.illuminatedFraction(at: date)

    XCTAssertEqual(events.sunriseMinute, 5 * 60 + 59 + 41.127 / 60, accuracy: 0.001)
    XCTAssertEqual(events.sunsetMinute, 19 * 60 + 59 + 36.857 / 60, accuracy: 0.001)
    XCTAssertEqual(moonPhase, 0.312_628_116_664, accuracy: 0.000_2)

    let morning = SolarSchedule.health.resolve(
      atMinute: 5 * 60 + 30,
      sunriseMinute: events.sunriseMinute,
      sunsetMinute: events.sunsetMinute,
      moonPhase: moonPhase
    )
    XCTAssertEqual(morning.adjustment.kelvin, 3_666, accuracy: 1)
    XCTAssertEqual(morning.adjustment.brightness, 0.833_346_56, accuracy: 0.000_1)

    let afternoon = SolarSchedule.health.resolve(
      atMinute: 15 * 60 + 30,
      sunriseMinute: events.sunriseMinute,
      sunsetMinute: events.sunsetMinute,
      moonPhase: MoonCalculator.illuminatedFraction(
        at: try XCTUnwrap(
          calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 9, hour: 15, minute: 30)
          )
        )
      )
    )
    XCTAssertEqual(afternoon.adjustment, DisplayAdjustment(kelvin: 5_000, brightness: 1))

    let eveningDate = try XCTUnwrap(
      calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 9, hour: 19, minute: 30)
      )
    )
    let evening = SolarSchedule.health.resolve(
      atMinute: 19 * 60 + 30,
      sunriseMinute: try XCTUnwrap(
        SolarCalculator.events(on: eveningDate, coordinate: coordinate, calendar: calendar)
      ).sunriseMinute,
      sunsetMinute: try XCTUnwrap(
        SolarCalculator.events(on: eveningDate, coordinate: coordinate, calendar: calendar)
      ).sunsetMinute,
      moonPhase: MoonCalculator.illuminatedFraction(at: eveningDate)
    )
    XCTAssertEqual(evening.adjustment.kelvin, 4_750)
    XCTAssertEqual(evening.adjustment.brightness, 0.968_820_34, accuracy: 0.000_1)

    let wake = SolarSchedule.health.resolve(
      atMinute: 3 * 60 + 30,
      sunriseMinute: events.sunriseMinute,
      sunsetMinute: events.sunsetMinute,
      moonPhase: MoonCalculator.illuminatedFraction(
        at: try XCTUnwrap(
          calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 9, hour: 3, minute: 30)
          )
        )
      )
    )
    XCTAssertEqual(wake.adjustment.kelvin, 3_050)
    XCTAssertEqual(wake.adjustment.brightness, 0.775, accuracy: 0.000_1)
    XCTAssertEqual(wake.phase, .transitionFromSleep(progress: 0.5))
  }

  func testHealthScheduleMatchesLegacyIrisAcrossTheFullDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let coordinate = GeographicCoordinate(
      latitude: 30.19280052185059,
      longitude: -118.3690032958984
    )
    let expected: [(hour: Int, minute: Int, kelvin: Int, brightness: Float)] = [
      (0, 0, 2_700, 0.75), (0, 30, 2_700, 0.75),
      (1, 0, 2_700, 0.75), (1, 30, 2_700, 0.75),
      (2, 0, 2_700, 0.75), (2, 30, 2_700, 0.75),
      (3, 0, 2_700, 0.75), (3, 30, 3_050, 0.775),
      (4, 0, 3_400, 0.8), (4, 30, 3_400, 0.8),
      (5, 0, 3_400, 0.8), (5, 30, 3_666, 0.833_346_56),
      (6, 0, 4_465, 0.933_235_70), (6, 30, 5_000, 1),
      (7, 0, 5_000, 1), (7, 30, 5_000, 1),
      (8, 0, 5_000, 1), (8, 30, 5_000, 1),
      (9, 0, 5_000, 1), (9, 30, 5_000, 1),
      (10, 0, 5_000, 1), (10, 30, 5_000, 1),
      (11, 0, 5_000, 1), (11, 30, 5_000, 1),
      (12, 0, 5_000, 1), (12, 30, 5_000, 1),
      (13, 0, 5_000, 1), (13, 30, 5_000, 1),
      (14, 0, 5_000, 1), (14, 30, 5_000, 1),
      (15, 0, 5_000, 1), (15, 30, 5_000, 1),
      (16, 0, 5_000, 1), (16, 30, 5_000, 1),
      (17, 0, 5_000, 1), (17, 30, 5_000, 1),
      (18, 0, 5_000, 1), (18, 30, 5_000, 1),
      (19, 0, 5_000, 1), (19, 30, 4_750, 0.968_820_34),
      (20, 0, 3_951, 0.868_925_93), (20, 30, 3_400, 0.8),
      (21, 0, 3_400, 0.8), (21, 30, 3_400, 0.8),
      (22, 0, 3_400, 0.8), (22, 30, 3_400, 0.8),
      (23, 0, 3_400, 0.8), (23, 30, 3_050, 0.775),
    ]

    for sample in expected {
      let date = try XCTUnwrap(
        calendar.date(
          from: DateComponents(
            year: 2026,
            month: 7,
            day: 9,
            hour: sample.hour,
            minute: sample.minute
          )
        )
      )
      let events = try XCTUnwrap(
        SolarCalculator.events(on: date, coordinate: coordinate, calendar: calendar)
      )
      let resolved = SolarSchedule.health.resolve(
        atMinute: Double(sample.hour * 60 + sample.minute),
        sunriseMinute: events.sunriseMinute,
        sunsetMinute: events.sunsetMinute,
        moonPhase: MoonCalculator.illuminatedFraction(at: date)
      )

      XCTAssertEqual(
        resolved.adjustment.kelvin,
        sample.kelvin,
        "Kelvin mismatch at \(sample.hour):\(sample.minute)"
      )
      XCTAssertEqual(
        resolved.adjustment.brightness,
        sample.brightness,
        accuracy: 0.000_2,
        "Brightness mismatch at \(sample.hour):\(sample.minute)"
      )
    }
  }

  func testLegacySolarEventsMatchAcrossTheYear() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let coordinate = GeographicCoordinate(
      latitude: 30.19280052185059,
      longitude: -118.3690032958984
    )
    let samples: [(month: Int, day: Int, sunrise: Double, sunset: Double)] = [
      (1, 9, 6 * 60 + 52 + 0.953 / 60, 17 * 60 + 10 + 35.911 / 60),
      (3, 20, 6 * 60 + 59 + 48.380 / 60, 19 * 60 + 5 + 15.374 / 60),
      (7, 9, 5 * 60 + 59 + 41.127 / 60, 19 * 60 + 59 + 36.857 / 60),
      (9, 22, 6 * 60 + 42 + 32.334 / 60, 18 * 60 + 53 + 13.770 / 60),
      (12, 21, 6 * 60 + 46 + 29.518 / 60, 16 * 60 + 58 + 18.662 / 60),
    ]

    for sample in samples {
      let date = try XCTUnwrap(
        calendar.date(
          from: DateComponents(year: 2026, month: sample.month, day: sample.day, hour: 12)
        )
      )
      let events = try XCTUnwrap(
        SolarCalculator.events(on: date, coordinate: coordinate, calendar: calendar)
      )
      XCTAssertEqual(events.sunriseMinute, sample.sunrise, accuracy: 0.001)
      XCTAssertEqual(events.sunsetMinute, sample.sunset, accuracy: 0.001)
    }
  }

  func testAutomaticLocationUsesCoarseCaptureThenFallsBackToManualCoordinate() {
    let captured = GeographicCoordinate(latitude: 37.77493, longitude: -122.41942)
    let manual = GeographicCoordinate(latitude: 40.7128, longitude: -74.006)

    var settings = SolarLocationSettings(
      source: .automatic,
      automaticCoordinate: captured,
      manualCoordinate: manual
    )

    XCTAssertEqual(
      settings.resolvedLocation,
      ResolvedSolarLocation(
        coordinate: GeographicCoordinate(latitude: 37.8, longitude: -122.4),
        source: .automatic
      )
    )

    settings.automaticCoordinate = nil
    XCTAssertEqual(
      settings.resolvedLocation,
      ResolvedSolarLocation(coordinate: manual, source: .manualFallback)
    )

    settings.source = .manual
    XCTAssertEqual(
      settings.resolvedLocation,
      ResolvedSolarLocation(coordinate: manual, source: .manual)
    )
  }

  func testPreviewSamplesCoverTheWholeDayAndExposeSolarAnchors() {
    let schedule = SolarSchedule.standard
    let preview = SchedulePreview.solar(
      schedule: schedule,
      sunriseMinute: 6 * 60,
      sunsetMinute: 18 * 60,
      sampleIntervalMinutes: 30
    )

    XCTAssertEqual(preview.samples.count, 49)
    XCTAssertEqual(preview.samples.first?.minute, 0)
    XCTAssertEqual(preview.samples.last?.minute, 1_440)
    XCTAssertEqual(preview.dayStartMinute, 6 * 60)
    XCTAssertEqual(preview.nightStartMinute, 18 * 60)
  }
}
