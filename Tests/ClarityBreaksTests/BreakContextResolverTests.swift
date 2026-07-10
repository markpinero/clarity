import XCTest

@testable import ClarityBreaks

final class BreakContextResolverTests: XCTestCase {
  func testIdleResetIsEmittedOnlyWhenTheUserReturnsFromAQualifiedNaturalBreak() {
    var resolver = BreakContextResolver()
    var configuration = BreakConfiguration.standard
    configuration.idleResetDuration = 5 * 60

    var resolution = resolver.resolve(
      BreakContextObservation(idleDuration: 4 * 60),
      configuration: configuration
    )
    XCTAssertEqual(resolution.reasons, [])
    XCTAssertFalse(resolution.resetFocusAfterIdle)

    resolution = resolver.resolve(
      BreakContextObservation(idleDuration: 5 * 60),
      configuration: configuration
    )
    XCTAssertEqual(resolution.reasons, [.idle])
    XCTAssertFalse(resolution.resetFocusAfterIdle)

    resolution = resolver.resolve(
      BreakContextObservation(idleDuration: 0),
      configuration: configuration
    )
    XCTAssertEqual(resolution.reasons, [])
    XCTAssertTrue(resolution.resetFocusAfterIdle)
  }

  func testEnabledSmartPauseSignalsMapToIndependentReasons() {
    var resolver = BreakContextResolver()
    let observation = BreakContextObservation(
      hasCalendarMeeting: true,
      hasActiveCall: true,
      hasVideoPlayback: true,
      hasActiveGame: true,
      isScreenSharing: true
    )

    let resolution = resolver.resolve(observation, configuration: .standard)

    XCTAssertEqual(
      resolution.reasons,
      [.calendarMeeting, .call, .videoPlayback, .gaming, .screenSharing]
    )
  }
}
