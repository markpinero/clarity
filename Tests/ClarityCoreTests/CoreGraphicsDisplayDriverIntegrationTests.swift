import XCTest

@testable import ClarityCore

final class CoreGraphicsDisplayDriverIntegrationTests: XCTestCase {
  func testEnumeratesOnlineDisplaysWithStableIdentifiersAndCapturesSupportedTables() throws {
    try requireHardwareTests()
    let driver = CoreGraphicsDisplayDriver()

    let displays = try driver.enumerateDisplays()

    XCTAssertFalse(displays.isEmpty)
    XCTAssertTrue(displays.allSatisfy { !$0.id.stableID.isEmpty })

    for display in displays where display.supportsGamma {
      let table = try driver.captureTransferTable(for: display.id)
      XCTAssertGreaterThan(table.red.count, 0)
      XCTAssertLessThanOrEqual(table.red.count, display.gammaTableCapacity)
      XCTAssertEqual(table.red.count, table.green.count)
      XCTAssertEqual(table.red.count, table.blue.count)
    }
  }

  func testAppliesAndRestoresASubtleBrightnessAdjustmentOnMainDisplay() throws {
    try requireHardwareTests()
    let driver = CoreGraphicsDisplayDriver()
    guard
      let display = try driver.enumerateDisplays().first(where: { $0.isMain && $0.supportsGamma })
    else {
      throw XCTSkip("The main display does not expose gamma transfer tables")
    }

    let baseline = try driver.captureTransferTable(for: display.id)
    let adjusted = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 6_500, brightness: 0.98),
      to: baseline
    )
    defer {
      try? driver.apply(baseline, to: display.id)
    }

    try driver.apply(adjusted, to: display.id)
    let applied = try driver.captureTransferTable(for: display.id)
    XCTAssertLessThan(maxDifference(applied, adjusted), 0.02)

    try driver.apply(baseline, to: display.id)
    let restored = try driver.captureTransferTable(for: display.id)
    XCTAssertLessThan(maxDifference(restored, baseline), 0.02)
  }

  private func requireHardwareTests() throws {
    guard ProcessInfo.processInfo.environment["CLARITY_RUN_HARDWARE_TESTS"] == "1" else {
      throw XCTSkip("Set CLARITY_RUN_HARDWARE_TESTS=1 to exercise the current displays")
    }
  }

  private func maxDifference(_ lhs: RGBTransferTable, _ rhs: RGBTransferTable) -> Float {
    let red = zip(lhs.red, rhs.red).map { abs($0 - $1) }.max() ?? 0
    let green = zip(lhs.green, rhs.green).map { abs($0 - $1) }.max() ?? 0
    let blue = zip(lhs.blue, rhs.blue).map { abs($0 - $1) }.max() ?? 0
    return max(red, green, blue)
  }
}
