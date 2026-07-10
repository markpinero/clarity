import XCTest

@testable import ClarityCore

final class DisplayTransformTests: XCTestCase {
  func testNeutralAdjustmentPreservesCapturedCalibration() throws {
    let baseline = try RGBTransferTable(
      red: [0, 0.2, 0.48, 0.78, 1],
      green: [0, 0.18, 0.46, 0.76, 0.99],
      blue: [0, 0.16, 0.44, 0.74, 0.98]
    )

    let result = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 6_500, brightness: 1),
      to: baseline
    )

    XCTAssertEqual(result, baseline)
  }

  func testBrightnessScalesEveryCapturedChannel() throws {
    let baseline = try RGBTransferTable(
      red: [0, 0.4, 1],
      green: [0, 0.3, 0.9],
      blue: [0, 0.2, 0.8]
    )

    let result = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 6_500, brightness: 0.5),
      to: baseline
    )

    XCTAssertEqual(result.red, [0, 0.2, 0.5])
    XCTAssertEqual(result.green, [0, 0.15, 0.45])
    XCTAssertEqual(result.blue, [0, 0.1, 0.4])
  }

  func testWarmTemperaturePreservesRedAndAttenuatesBlueMost() throws {
    let baseline = try RGBTransferTable(
      red: [0, 0.5, 1],
      green: [0, 0.5, 1],
      blue: [0, 0.5, 1]
    )

    let result = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 3_000, brightness: 1),
      to: baseline
    )

    XCTAssertEqual(result.red.last!, 1, accuracy: 0.001)
    XCTAssertEqual(result.green.last!, 0.70, accuracy: 0.03)
    XCTAssertEqual(result.blue.last!, 0.44, accuracy: 0.03)
    XCTAssertGreaterThan(result.green.last!, result.blue.last!)
  }

  func testCurrentLegacyIrisGammaEndpointsMatchMeasuredColorRamp() throws {
    let baseline = try RGBTransferTable(
      red: [0, 1],
      green: [0, 1],
      blue: [0, 1]
    )

    let day = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 5_000, brightness: 1),
      to: baseline
    )
    XCTAssertEqual(day.red[1], 1, accuracy: 0.000_001)
    XCTAssertEqual(day.green[1], 0.901_982_307, accuracy: 0.000_001)
    XCTAssertEqual(day.blue[1], 0.814_655_006, accuracy: 0.000_001)

    let night = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 3_400, brightness: 0.8),
      to: baseline
    )
    XCTAssertEqual(night.red[1], 0.800_000_012, accuracy: 0.000_001)
    XCTAssertEqual(night.green[1], 0.615_106_463, accuracy: 0.000_001)
    XCTAssertEqual(night.blue[1], 0.419_418_573, accuracy: 0.000_001)

    let sleep = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 2_700, brightness: 0.75),
      to: baseline
    )
    XCTAssertEqual(sleep.red[1], 0.75, accuracy: 0.000_001)
    XCTAssertEqual(sleep.green[1], 0.507_343_650, accuracy: 0.000_001)
    XCTAssertEqual(sleep.blue[1], 0.260_900_676, accuracy: 0.000_001)

    let interpolated = DisplayTransform.apply(
      adjustment: DisplayAdjustment(kelvin: 4_450, brightness: 1),
      to: baseline
    )
    XCTAssertEqual(interpolated.red[1], 1, accuracy: 0.000_001)
    XCTAssertEqual(interpolated.green[1], 0.864_894_629, accuracy: 0.000_001)
    XCTAssertEqual(interpolated.blue[1], 0.728_482_842, accuracy: 0.000_001)
  }

  func testOutOfRangeInputsProduceFiniteBoundedMonotonicTables() throws {
    let baseline = try RGBTransferTable(
      red: [0, 0.2, 0.7, 1],
      green: [0, 0.3, 0.8, 1],
      blue: [0, 0.1, 0.6, 1]
    )

    for adjustment in [
      DisplayAdjustment(kelvin: -10_000, brightness: 2),
      DisplayAdjustment(kelvin: 100_000, brightness: -1),
    ] {
      let result = DisplayTransform.apply(adjustment: adjustment, to: baseline)

      for channel in [result.red, result.green, result.blue] {
        XCTAssertTrue(channel.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertEqual(channel, channel.sorted())
      }
    }
  }

  func testTransferTableRejectsEmptyOrMismatchedChannels() {
    XCTAssertThrowsError(try RGBTransferTable(red: [], green: [], blue: []))
    XCTAssertThrowsError(try RGBTransferTable(red: [0, 1], green: [0], blue: [0, 1]))
  }
}
