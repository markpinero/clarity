import XCTest

@testable import ClarityCore

final class DisplayCoordinatorTests: XCTestCase {
  func testRefreshCapturesBaselineOncePerStableDisplay() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)

    try coordinator.refreshDisplays()
    try coordinator.refreshDisplays()

    XCTAssertEqual(coordinator.displays, [display])
    XCTAssertEqual(driver.captureCalls, [display.id])
  }

  func testApplyTransformsEverySelectedDisplayFromItsCapturedBaseline() throws {
    let displayA = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let displayB = DisplayDescriptor.testDisplay(stableID: "display-b", runtimeID: 20)
    let baselineA = try RGBTransferTable.identity(samples: 3)
    let baselineB = try RGBTransferTable(
      red: [0, 0.4, 0.8],
      green: [0, 0.3, 0.7],
      blue: [0, 0.2, 0.6]
    )
    let driver = FakeDisplayDriver(
      displays: [displayA, displayB],
      baselines: [
        displayA.id.stableID: baselineA,
        displayB.id.stableID: baselineB,
      ]
    )
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 6_500, brightness: 0.5)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [displayA.id.stableID, displayB.id.stableID])

    XCTAssertEqual(driver.applyCalls.map(\.0), [displayA.id, displayB.id])
    XCTAssertEqual(driver.applyCalls[0].1.red, [0, 0.25, 0.5])
    XCTAssertEqual(driver.applyCalls[1].1.red, [0, 0.2, 0.4])
    XCTAssertEqual(
      coordinator.mode,
      .applied([displayA.id.stableID: adjustment, displayB.id.stableID: adjustment])
    )
  }

  func testPauseRestoresCapturedBaselinesAndResumeReappliesAdjustment() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [display.id.stableID])
    try coordinator.pause()

    XCTAssertEqual(driver.applyCalls.last!.0, display.id)
    XCTAssertEqual(driver.applyCalls.last!.1, baseline)
    XCTAssertEqual(coordinator.mode, .paused([display.id.stableID: adjustment]))

    try coordinator.resume()

    XCTAssertEqual(driver.applyCalls.count, 3)
    XCTAssertNotEqual(driver.applyCalls.last!.1, baseline)
    XCTAssertEqual(coordinator.mode, .applied([display.id.stableID: adjustment]))
  }

  func testApplyingToReducedSelectionRestoresDeselectedDisplay() throws {
    let displayA = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let displayB = DisplayDescriptor.testDisplay(stableID: "display-b", runtimeID: 20)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(
      displays: [displayA, displayB],
      baselines: [displayA.id.stableID: baseline, displayB.id.stableID: baseline]
    )
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [displayA.id.stableID, displayB.id.stableID])
    driver.applyCalls.removeAll()

    try coordinator.apply(adjustment: adjustment, to: [displayA.id.stableID])

    XCTAssertEqual(driver.applyCalls.map(\.0), [displayB.id, displayA.id])
    if driver.applyCalls.count == 2 {
      XCTAssertEqual(driver.applyCalls[0].1, baseline)
      XCTAssertNotEqual(driver.applyCalls[1].1, baseline)
    }
    XCTAssertEqual(coordinator.mode, .applied([displayA.id.stableID: adjustment]))
  }

  func testResetRestoresBaselineAndReturnsToIdle() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)

    try coordinator.refreshDisplays()
    try coordinator.apply(
      adjustment: DisplayAdjustment(kelvin: 3_000, brightness: 0.8),
      to: [display.id.stableID]
    )
    try coordinator.reset()

    XCTAssertEqual(driver.applyCalls.last!.1, baseline)
    XCTAssertEqual(coordinator.mode, .idle)
  }

  func testTopologyChangeReusesStableBaselineAndReappliesToNewRuntimeID() throws {
    let originalDisplay = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let reconfiguredDisplay = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 42)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(
      displays: [originalDisplay],
      baselines: [originalDisplay.id.stableID: baseline]
    )
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [originalDisplay.id.stableID])
    driver.displays = [reconfiguredDisplay]
    driver.applyCalls.removeAll()

    try coordinator.handleTopologyChange()

    XCTAssertEqual(driver.captureCalls, [originalDisplay.id])
    XCTAssertEqual(driver.applyCalls.map(\.0), [reconfiguredDisplay.id])
    XCTAssertEqual(coordinator.displays, [reconfiguredDisplay])
    XCTAssertEqual(coordinator.mode, .applied([originalDisplay.id.stableID: adjustment]))
  }

  func testPartialApplyFailureRollsBackDisplaysAlreadyChanged() throws {
    let displayA = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let displayB = DisplayDescriptor.testDisplay(stableID: "display-b", runtimeID: 20)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(
      displays: [displayA, displayB],
      baselines: [displayA.id.stableID: baseline, displayB.id.stableID: baseline]
    )
    driver.applyFailureStableIDs = [displayB.id.stableID]
    let coordinator = DisplayCoordinator(driver: driver)

    try coordinator.refreshDisplays()

    XCTAssertThrowsError(
      try coordinator.apply(
        adjustment: DisplayAdjustment(kelvin: 3_000, brightness: 0.8),
        to: [displayA.id.stableID, displayB.id.stableID]
      )
    )
    XCTAssertEqual(driver.applyCalls.map(\.0), [displayA.id, displayA.id])
    if driver.applyCalls.count == 2 {
      XCTAssertNotEqual(driver.applyCalls[0].1, baseline)
      XCTAssertEqual(driver.applyCalls[1].1, baseline)
    }
    XCTAssertEqual(coordinator.mode, .idle)
  }

  func testAppliesDifferentAdjustmentsToIndividualDisplays() throws {
    let displayA = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let displayB = DisplayDescriptor.testDisplay(stableID: "display-b", runtimeID: 20)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(
      displays: [displayA, displayB],
      baselines: [displayA.id.stableID: baseline, displayB.id.stableID: baseline]
    )
    let coordinator = DisplayCoordinator(driver: driver)
    let targets = [
      displayA.id.stableID: DisplayAdjustment(kelvin: 6_500, brightness: 0.5),
      displayB.id.stableID: DisplayAdjustment(kelvin: 3_000, brightness: 0.8),
    ]

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustments: targets)

    XCTAssertEqual(driver.applyCalls.map(\.0), [displayA.id, displayB.id])
    XCTAssertEqual(driver.applyCalls[0].1.red.last, 0.5)
    XCTAssertEqual(driver.applyCalls[1].1.red.last, 0.8)
    XCTAssertEqual(coordinator.mode, .applied(targets))
  }

  func testManualTimingDefersWritesUntilAdvanced() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)
    let start = Date(timeIntervalSince1970: 1_000)

    try coordinator.refreshDisplays()
    driver.applyCalls.removeAll()
    try coordinator.apply(
      adjustment: adjustment,
      to: [display.id.stableID],
      timing: .manual,
      at: start
    )

    XCTAssertTrue(driver.applyCalls.isEmpty)
    XCTAssertEqual(coordinator.mode, .applied([display.id.stableID: adjustment]))
  }

  func testAdvanceRampWritesInterpolatedFramesAndSettlesExactly() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)
    let start = Date(timeIntervalSince1970: 2_000)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [display.id.stableID], timing: .manual, at: start)

    let half = try coordinator.advanceRamp(at: start.addingTimeInterval(0.4))
    XCTAssertTrue(half.isLive)
    let midTable = driver.applyCalls.last!.1
    XCTAssertNotEqual(midTable, baseline)
    XCTAssertNotEqual(midTable, DisplayTransform.apply(adjustment: adjustment, to: baseline))

    let done = try coordinator.advanceRamp(at: start.addingTimeInterval(0.8))
    XCTAssertFalse(done.isLive)
    XCTAssertEqual(
      driver.applyCalls.last!.1,
      DisplayTransform.apply(adjustment: adjustment, to: baseline)
    )
  }

  func testRetargetMidRampContinuesFromCurrentFactors() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustmentA = DisplayAdjustment(kelvin: 4_500, brightness: 1)
    let adjustmentB = DisplayAdjustment(kelvin: 2_500, brightness: 0.9)
    let start = Date(timeIntervalSince1970: 3_000)

    try coordinator.refreshDisplays()
    try coordinator.apply(
      adjustment: adjustmentA,
      to: [display.id.stableID],
      timing: .manual,
      at: start
    )
    _ = try coordinator.advanceRamp(at: start.addingTimeInterval(0.4))
    let midTable = driver.applyCalls.last!.1

    let retargetAt = start.addingTimeInterval(0.4)
    try coordinator.apply(
      adjustment: adjustmentB,
      to: [display.id.stableID],
      timing: .manual,
      at: retargetAt
    )
    _ = try coordinator.advanceRamp(at: retargetAt.addingTimeInterval(0.1))

    let frame = driver.applyCalls.last!.1
    let targetB = DisplayTransform.apply(adjustment: adjustmentB, to: baseline)
    XCTAssertLessThan(frame.green.last!, midTable.green.last!)
    XCTAssertGreaterThan(frame.green.last!, targetB.green.last!)
    XCTAssertLessThan(frame.blue.last!, midTable.blue.last!)
    XCTAssertGreaterThan(frame.blue.last!, targetB.blue.last!)
  }

  func testPauseRampRestoresBaselineExactly() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)
    let start = Date(timeIntervalSince1970: 4_000)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [display.id.stableID])
    driver.applyCalls.removeAll()
    try coordinator.pause(timing: .manual, at: start)

    XCTAssertTrue(driver.applyCalls.isEmpty)
    let done = try coordinator.advanceRamp(at: start.addingTimeInterval(0.8))
    XCTAssertFalse(done.isLive)
    XCTAssertEqual(driver.applyCalls.last!.1, baseline)
    XCTAssertEqual(coordinator.mode, .paused([display.id.stableID: adjustment]))
  }

  func testAdvanceRampFailureClearsRampsAndThrows() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let start = Date(timeIntervalSince1970: 5_000)

    try coordinator.refreshDisplays()
    try coordinator.apply(
      adjustment: DisplayAdjustment(kelvin: 3_000, brightness: 0.8),
      to: [display.id.stableID],
      timing: .manual,
      at: start
    )
    driver.applyFailureStableIDs = [display.id.stableID]

    XCTAssertThrowsError(try coordinator.advanceRamp(at: start.addingTimeInterval(0.4)))
    XCTAssertEqual(coordinator.mode, .idle)

    driver.applyFailureStableIDs = []
    let status = try coordinator.advanceRamp(at: start.addingTimeInterval(0.5))
    XCTAssertFalse(status.isLive)
  }

  func testSuggestedIntervalIsShortForManualAndLongForSchedule() throws {
    let display = DisplayDescriptor.testDisplay(stableID: "display-a", runtimeID: 10)
    let baseline = try RGBTransferTable.identity(samples: 3)
    let driver = FakeDisplayDriver(displays: [display], baselines: [display.id.stableID: baseline])
    let coordinator = DisplayCoordinator(driver: driver)
    let adjustment = DisplayAdjustment(kelvin: 3_000, brightness: 0.8)
    let start = Date(timeIntervalSince1970: 6_000)

    try coordinator.refreshDisplays()
    try coordinator.apply(adjustment: adjustment, to: [display.id.stableID], timing: .manual, at: start)
    let manualStatus = try coordinator.advanceRamp(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(manualStatus.nextInterval, 1.0 / 30, accuracy: 1e-9)

    _ = try coordinator.advanceRamp(at: start.addingTimeInterval(0.8))
    try coordinator.apply(
      adjustment: DisplayAdjustment(kelvin: 4_000, brightness: 0.9),
      to: [display.id.stableID],
      timing: .schedule,
      at: start.addingTimeInterval(1)
    )
    let scheduleStatus = try coordinator.advanceRamp(at: start.addingTimeInterval(1.5))
    XCTAssertEqual(scheduleStatus.nextInterval, 0.25, accuracy: 1e-9)
  }
}

private final class FakeDisplayDriver: DisplayDriver {
  var displays: [DisplayDescriptor]
  var baselines: [String: RGBTransferTable]
  var captureCalls: [DisplayIdentifier] = []
  var applyCalls: [(DisplayIdentifier, RGBTransferTable)] = []
  var applyFailureStableIDs: Set<String> = []

  init(displays: [DisplayDescriptor], baselines: [String: RGBTransferTable]) {
    self.displays = displays
    self.baselines = baselines
  }

  func enumerateDisplays() throws -> [DisplayDescriptor] {
    displays
  }

  func captureTransferTable(for display: DisplayIdentifier) throws -> RGBTransferTable {
    captureCalls.append(display)
    return baselines[display.stableID]!
  }

  func apply(_ table: RGBTransferTable, to display: DisplayIdentifier) throws {
    if applyFailureStableIDs.contains(display.stableID) {
      throw FakeDisplayDriverError.applyFailed
    }
    applyCalls.append((display, table))
  }
}

private enum FakeDisplayDriverError: Error {
  case applyFailed
}

extension DisplayDescriptor {
  fileprivate static func testDisplay(stableID: String, runtimeID: UInt32) -> DisplayDescriptor {
    DisplayDescriptor(
      id: DisplayIdentifier(stableID: stableID, runtimeID: runtimeID),
      name: stableID,
      isMain: runtimeID == 10,
      isBuiltin: runtimeID == 10,
      pixelWidth: 1_920,
      pixelHeight: 1_080,
      gammaTableCapacity: 256
    )
  }
}

extension RGBTransferTable {
  fileprivate static func identity(samples: Int) throws -> RGBTransferTable {
    let denominator = Float(samples - 1)
    let values = (0..<samples).map { Float($0) / denominator }
    return try RGBTransferTable(red: values, green: values, blue: values)
  }
}
