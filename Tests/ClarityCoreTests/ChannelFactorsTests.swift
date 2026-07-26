import XCTest

@testable import ClarityCore

final class ChannelFactorsTests: XCTestCase {
  func testIdentityLeavesChannelsUnchanged() {
    let factors = ChannelFactors.identity
    XCTAssertEqual(factors.red, 1)
    XCTAssertEqual(factors.green, 1)
    XCTAssertEqual(factors.blue, 1)
  }

  func testScaledMultipliesEveryChannelAndClampsBrightness() {
    let factors = ChannelFactors(red: 0.8, green: 0.6, blue: 0.4).scaled(by: 0.5)
    XCTAssertEqual(factors.red, 0.4, accuracy: 1e-6)
    XCTAssertEqual(factors.green, 0.3, accuracy: 1e-6)
    XCTAssertEqual(factors.blue, 0.2, accuracy: 1e-6)

    let clamped = ChannelFactors.identity.scaled(by: 2)
    XCTAssertEqual(clamped, .identity)
    let floored = ChannelFactors.identity.scaled(by: -1)
    XCTAssertEqual(floored, ChannelFactors(red: 0, green: 0, blue: 0))
  }

  func testInterpolatedHitsExactEndpointsAndMidpoint() {
    let from = ChannelFactors(red: 1, green: 0.5, blue: 0)
    let to = ChannelFactors(red: 0, green: 0.5, blue: 1)
    XCTAssertEqual(from.interpolated(to: to, progress: 0), from)
    XCTAssertEqual(from.interpolated(to: to, progress: 1), to)
    let mid = from.interpolated(to: to, progress: 0.5)
    XCTAssertEqual(mid.red, 0.5, accuracy: 1e-6)
    XCTAssertEqual(mid.blue, 0.5, accuracy: 1e-6)
    XCTAssertEqual(from.interpolated(to: to, progress: -1), from)
    XCTAssertEqual(from.interpolated(to: to, progress: 2), to)
  }
}
