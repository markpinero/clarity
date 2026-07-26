import Foundation
import XCTest

@testable import ClarityDiagnostics

final class BreakOverlayProgressTests: XCTestCase {
  func testFractionTracksTheWholeDuration() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let deadline = start.addingTimeInterval(20)

    XCTAssertEqual(
      BreakOverlayProgress.fraction(deadline: deadline, at: start, totalSeconds: 20),
      1
    )
    XCTAssertEqual(
      BreakOverlayProgress.fraction(
        deadline: deadline,
        at: start.addingTimeInterval(5),
        totalSeconds: 20
      ),
      0.75
    )
    XCTAssertEqual(
      BreakOverlayProgress.fraction(deadline: deadline, at: deadline, totalSeconds: 20),
      0
    )
  }

  func testFractionClampsOutsideTheDuration() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let deadline = start.addingTimeInterval(20)

    XCTAssertEqual(
      BreakOverlayProgress.fraction(
        deadline: deadline,
        at: start.addingTimeInterval(-1),
        totalSeconds: 20
      ),
      1
    )
    XCTAssertEqual(
      BreakOverlayProgress.fraction(
        deadline: deadline,
        at: deadline.addingTimeInterval(1),
        totalSeconds: 20
      ),
      0
    )
    XCTAssertEqual(
      BreakOverlayProgress.fraction(deadline: nil, at: start, totalSeconds: 20),
      0
    )
  }
}
