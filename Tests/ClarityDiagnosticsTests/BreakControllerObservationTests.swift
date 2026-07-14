import ClarityBreaks
import Combine
import Foundation
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

    let observation = controller.$snapshot.dropFirst().sink { _ in
      wasInvalidated.set()
    }

    withExtendedLifetime(observation) {
      controller.tick(at: now)
    }

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
