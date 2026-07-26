import ClarityBreaks
import XCTest

@testable import ClarityDiagnostics

final class BreakMenuVisibilityTests: XCTestCase {
  func testStartBreakNowIsVisibleWhileAutomaticallyPaused() {
    XCTAssertTrue(
      BreakMenuVisibility.showsStartBreak(
        isEnabled: true,
        phase: .paused
      )
    )
  }
}
