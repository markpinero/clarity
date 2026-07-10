import Foundation
import XCTest

@testable import ClarityCore

final class PreferencesRepositoryTests: XCTestCase {
  func testSavedPreferencesLoadInANewRepositoryInstance() throws {
    let suiteName = "PreferencesRepositoryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let expected = AppPreferences(
      isEnabled: true,
      isPaused: false,
      controlMode: .automatic,
      selectedProfile: .sleep,
      schedule: ClockSchedule(
        dayStartMinute: 8 * 60,
        nightStartMinute: 22 * 60,
        transitionMinutes: 90,
        dayProfile: .reading,
        nightProfile: .sleep
      )
    )

    try PreferencesRepository(defaults: defaults).save(expected)

    XCTAssertEqual(PreferencesRepository(defaults: defaults).load(), expected)
  }

  func testLoadsSliceOnePreferencesWithSliceTwoDefaults() throws {
    struct SliceOnePreferences: Encodable {
      let isEnabled = true
      let isPaused = false
      let controlMode = ControlMode.automatic
      let selectedProfile = ClarityProfile.evening
      let schedule = ClockSchedule.standard
    }

    let suiteName = "PreferencesRepositoryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(try JSONEncoder().encode(SliceOnePreferences()), forKey: "app-preferences.v1")

    let loaded = PreferencesRepository(defaults: defaults).load()

    XCTAssertTrue(loaded.isEnabled)
    XCTAssertFalse(loaded.hideFromAppSwitcher)
    XCTAssertEqual(loaded.selectedProfile, .evening)
    XCTAssertEqual(loaded.automaticScheduleKind, .clock)
    XCTAssertEqual(loaded.solarSchedule, .standard)
    XCTAssertEqual(loaded.solarLocation, .standard)
    XCTAssertTrue(loaded.displaySettings.isEmpty)
  }

  func testPersistsAppSwitcherVisibility() throws {
    let suiteName = "PreferencesRepositoryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var expected = AppPreferences.standard
    expected.hideFromAppSwitcher = true

    try PreferencesRepository(defaults: defaults).save(expected)

    XCTAssertTrue(PreferencesRepository(defaults: defaults).load().hideFromAppSwitcher)
  }

  func testMigratesPreferencesFromLegacyBundleDomain() throws {
    let currentSuite = "PreferencesRepositoryTests.current.\(UUID().uuidString)"
    let legacySuite = "PreferencesRepositoryTests.legacy.\(UUID().uuidString)"
    let current = try XCTUnwrap(UserDefaults(suiteName: currentSuite))
    let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
    defer {
      current.removePersistentDomain(forName: currentSuite)
      legacy.removePersistentDomain(forName: legacySuite)
    }

    var expected = AppPreferences.standard
    expected.isEnabled = true
    try PreferencesRepository(defaults: legacy).save(expected)

    let repository = PreferencesRepository(defaults: current, legacyDefaults: legacy)
    XCTAssertEqual(repository.load(), expected)
    XCTAssertEqual(PreferencesRepository(defaults: current).load(), expected)
  }
}
