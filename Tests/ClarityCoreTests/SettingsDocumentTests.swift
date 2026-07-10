import XCTest

@testable import ClarityCore

final class SettingsDocumentTests: XCTestCase {
  func testSettingsDocumentRoundTripsPreferencesAndAutomationRules() throws {
    var preferences = AppPreferences.standard
    preferences.pauseInFullscreen = true
    preferences.hideFromAppSwitcher = true
    preferences.activeAppRules = [
      ActiveAppRule(
        bundleIdentifier: "com.example.Reader",
        displayName: "Reader",
        action: .profile(.reading)
      )
    ]

    let data = try SettingsDocument.encode(preferences)

    XCTAssertEqual(try SettingsDocument.decode(data), preferences)
  }

  func testSettingsDocumentRejectsUnsupportedFutureVersions() throws {
    let data = Data(
      """
      {"formatVersion":999,"preferences":{}}
      """.utf8
    )

    XCTAssertThrowsError(try SettingsDocument.decode(data)) { error in
      XCTAssertEqual(error as? SettingsDocumentError, .unsupportedVersion(999))
    }
  }
}
