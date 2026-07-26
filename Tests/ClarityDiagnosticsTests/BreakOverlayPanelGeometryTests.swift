import AppKit
import XCTest

@testable import ClarityDiagnostics

final class BreakOverlayPanelGeometryTests: XCTestCase {
  func testFullScreenPanelUsesCoordinatesRelativeToDisplayAbovePrimary() {
    let externalDisplay = CGRect(x: -204, y: 982, width: 1_920, height: 1_080)

    XCTAssertEqual(
      BreakOverlayPanelGeometry.contentRect(for: externalDisplay, on: externalDisplay),
      CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
    )
  }

  func testCountdownPanelUsesCoordinatesRelativeToOffsetDisplay() {
    let externalDisplay = CGRect(x: 1_512, y: 180, width: 1_920, height: 1_080)
    let countdownFrame = CGRect(x: 2_257, y: 1_062, width: 430, height: 156)

    XCTAssertEqual(
      BreakOverlayPanelGeometry.contentRect(for: countdownFrame, on: externalDisplay),
      CGRect(x: 745, y: 882, width: 430, height: 156)
    )
  }
}
