import XCTest

@testable import ClarityCore

final class DisplayPolicyTests: XCTestCase {
  func testEnabledManualModeUsesSelectedProfile() {
    let preferences = AppPreferences(
      isEnabled: true,
      isPaused: false,
      controlMode: .manual,
      selectedProfile: .reading,
      schedule: .standard
    )

    let decision = DisplayPolicy.resolve(preferences: preferences, atMinute: 12 * 60)

    XCTAssertEqual(decision.adjustment, ClarityProfile.reading.adjustment)
    XCTAssertEqual(decision.source, .manual(profile: .reading))
  }

  func testAutomaticModeUsesClockSchedule() {
    var preferences = AppPreferences.standard
    preferences.isEnabled = true
    preferences.controlMode = .automatic

    let decision = DisplayPolicy.resolve(preferences: preferences, atMinute: 20 * 60 + 30)

    XCTAssertEqual(decision.adjustment?.kelvin, 4_200)
    XCTAssertEqual(
      decision.source,
      .automatic(phase: .transitionToNight(progress: 0.5))
    )
  }

  func testDisabledAndPausedPoliciesDoNotRequestDisplayChanges() {
    var preferences = AppPreferences.standard

    var decision = DisplayPolicy.resolve(preferences: preferences, atMinute: 12 * 60)
    XCTAssertNil(decision.adjustment)
    XCTAssertEqual(decision.source, .disabled)

    preferences.isEnabled = true
    preferences.isPaused = true
    decision = DisplayPolicy.resolve(preferences: preferences, atMinute: 12 * 60)
    XCTAssertNil(decision.adjustment)
    XCTAssertEqual(decision.source, .paused)
  }

  func testAutomaticSolarModeUsesResolvedLocation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let date = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))
    )
    var preferences = AppPreferences.standard
    preferences.isEnabled = true
    preferences.controlMode = .automatic
    preferences.automaticScheduleKind = .solar
    preferences.solarLocation = SolarLocationSettings(
      source: .manual,
      manualCoordinate: GeographicCoordinate(latitude: 51.4769, longitude: 0)
    )

    let decision = DisplayPolicy.resolve(
      preferences: preferences,
      at: date,
      calendar: calendar
    )

    XCTAssertEqual(decision.adjustment, ClarityProfile.health.adjustment)
    guard case .solar(let events, .manual) = decision.scheduleBasis else {
      return XCTFail("Expected a manual-location solar decision")
    }
    XCTAssertEqual(events.sunriseMinute, 6 * 60 + 3, accuracy: 15)
  }

  func testSolarModeWithoutLocationFallsBackToClockSchedule() {
    var preferences = AppPreferences.standard
    preferences.isEnabled = true
    preferences.controlMode = .automatic
    preferences.automaticScheduleKind = .solar
    preferences.solarLocation = SolarLocationSettings(source: .automatic)

    let decision = DisplayPolicy.resolve(preferences: preferences, atMinute: 12 * 60)

    XCTAssertEqual(decision.adjustment, ClarityProfile.health.adjustment)
    XCTAssertEqual(decision.scheduleBasis, .clockFallback(.locationUnavailable))
  }

  func testPerDisplaySettingsDisableAndOverrideGlobalAdjustment() {
    let global = ClarityProfile.reading.adjustment
    let settings: [String: DisplaySettings] = [
      "display-b": DisplaySettings(isEnabled: false),
      "display-c": DisplaySettings(isEnabled: true, profileOverride: .sleep),
    ]

    let targets = DisplayPolicy.targetAdjustments(
      globalAdjustment: global,
      stableIDs: ["display-a", "display-b", "display-c"],
      displaySettings: settings
    )

    XCTAssertEqual(
      targets,
      [
        "display-a": global,
        "display-c": ClarityProfile.sleep.adjustment,
      ]
    )
  }
}
