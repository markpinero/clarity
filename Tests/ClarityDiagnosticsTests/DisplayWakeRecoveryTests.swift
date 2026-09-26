import XCTest

@testable import ClarityDiagnostics

@MainActor
final class DisplayWakeRecoveryTests: XCTestCase {
  func testWakeReappliesThroughDisplaySettlingWindow() {
    var filterIsApplied = false
    var scheduledActions: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
    let recovery = DisplayWakeRecovery(
      retryDelays: [0, 1, 5],
      schedule: { delay, action in
        scheduledActions.append((delay, action))
        return {}
      },
      recover: {
        filterIsApplied = true
      }
    )

    recovery.start()

    XCTAssertTrue(filterIsApplied)
    XCTAssertEqual(scheduledActions.map(\.delay), [1, 5])

    filterIsApplied = false
    scheduledActions[0].action()
    XCTAssertTrue(filterIsApplied)

    filterIsApplied = false
    scheduledActions[1].action()
    XCTAssertTrue(filterIsApplied)
  }

  func testRepeatedWakeNotificationReplacesPendingRetries() {
    var cancellations = 0
    let recovery = DisplayWakeRecovery(
      retryDelays: [0, 1, 5],
      schedule: { _, _ in
        return { cancellations += 1 }
      },
      recover: {}
    )

    recovery.start()
    recovery.start()

    XCTAssertEqual(cancellations, 2)
  }
}
