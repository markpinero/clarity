import XCTest

@testable import ClarityCore

final class RampTimingTests: XCTestCase {
  func testPresetDurations() {
    XCTAssertEqual(RampTiming.instant.duration, 0)
    XCTAssertEqual(RampTiming.manual.duration, 0.8)
    XCTAssertEqual(RampTiming.schedule.duration, 30)
  }

  func testLinearEasingIsProportional() {
    let timing = RampTiming(duration: 10, easing: .linear)
    XCTAssertEqual(timing.eased(progress: 0.25), 0.25, accuracy: 1e-6)
  }

  func testSmoothstepEasesBothEndsAndKeepsEndpoints() {
    let timing = RampTiming(duration: 10, easing: .smoothstep)
    XCTAssertEqual(timing.eased(progress: 0), 0, accuracy: 1e-6)
    XCTAssertEqual(timing.eased(progress: 1), 1, accuracy: 1e-6)
    XCTAssertEqual(timing.eased(progress: 0.5), 0.5, accuracy: 1e-6)
    XCTAssertLessThan(timing.eased(progress: 0.1), 0.1)
    XCTAssertGreaterThan(timing.eased(progress: 0.9), 0.9)
  }
}
