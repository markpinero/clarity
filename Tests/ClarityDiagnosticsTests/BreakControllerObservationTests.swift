import ClarityBreaks
import Foundation
import Observation
import XCTest

@testable import ClarityDiagnostics

@MainActor
final class BreakControllerObservationTests: XCTestCase {
  func testTimeOnlyTickDoesNotInvalidateSnapshotObservers() {
    let now = Date()
    let store = StubBreakStore(
      document: BreakStateDocument(
        configuration: .standard,
        snapshot: BreakSnapshot(
          phase: .focusing,
          phaseDeadline: now.addingTimeInterval(60)
        )
      )
    )
    let controller = BreakController(store: store)
    let wasInvalidated = LockedFlag()

    withObservationTracking {
      _ = controller.snapshot
    } onChange: {
      wasInvalidated.set()
    }

    controller.tick(at: now)

    XCTAssertFalse(wasInvalidated.value)
  }
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = false

  var value: Bool {
    lock.withLock { storage }
  }

  func set() {
    lock.withLock { storage = true }
  }
}

private final class StubBreakStore: BreakStore {
  private let document: BreakStateDocument

  init(document: BreakStateDocument) {
    self.document = document
  }

  func load() -> BreakStateDocument {
    document
  }

  func save(_ document: BreakStateDocument) throws {}
}
