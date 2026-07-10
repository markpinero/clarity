import XCTest

@testable import ClarityCore

final class AutomationPolicyTests: XCTestCase {
  func testActiveApplicationPauseRuleTemporarilySuppressesDisplayChanges() {
    var preferences = AppPreferences.standard
    preferences.isEnabled = true
    preferences.activeAppRules = [
      ActiveAppRule(
        bundleIdentifier: "com.example.Video",
        displayName: "Video",
        action: .pause
      )
    ]

    let decision = DisplayPolicy.resolve(
      preferences: preferences,
      atMinute: 12 * 60,
      context: AutomationContext(activeApplicationBundleIdentifier: "com.example.Video")
    )

    XCTAssertNil(decision.adjustment)
    XCTAssertEqual(
      decision.source,
      .automationPaused(.activeApplication(bundleIdentifier: "com.example.Video"))
    )
  }

  func testActiveApplicationProfileRuleOverridesManualAndScheduledProfiles() {
    var preferences = AppPreferences.standard
    preferences.isEnabled = true
    preferences.controlMode = .manual
    preferences.selectedProfile = .health
    preferences.activeAppRules = [
      ActiveAppRule(
        bundleIdentifier: "com.example.Reader",
        displayName: "Reader",
        action: .profile(.reading)
      )
    ]

    let decision = DisplayPolicy.resolve(
      preferences: preferences,
      atMinute: 12 * 60,
      context: AutomationContext(activeApplicationBundleIdentifier: "com.example.Reader")
    )

    XCTAssertEqual(decision.adjustment, ClarityProfile.reading.adjustment)
    XCTAssertEqual(
      decision.source,
      .automationProfile(.reading, bundleIdentifier: "com.example.Reader")
    )
  }

  func testFullscreenPauseIsPermissionFreeContextAndDoesNotOverrideOffOrManualPause() {
    var preferences = AppPreferences.standard
    preferences.pauseInFullscreen = true
    let fullscreen = AutomationContext(isActiveApplicationFullscreen: true)

    var decision = DisplayPolicy.resolve(
      preferences: preferences,
      atMinute: 12 * 60,
      context: fullscreen
    )
    XCTAssertEqual(decision.source, .disabled)

    preferences.isEnabled = true
    preferences.isPaused = true
    decision = DisplayPolicy.resolve(
      preferences: preferences,
      atMinute: 12 * 60,
      context: fullscreen
    )
    XCTAssertEqual(decision.source, .paused)

    preferences.isPaused = false
    decision = DisplayPolicy.resolve(
      preferences: preferences,
      atMinute: 12 * 60,
      context: fullscreen
    )
    XCTAssertEqual(decision.source, .automationPaused(.fullscreen))
  }
}
