import ClarityBreaks
import XCTest

@testable import ClarityDiagnostics

@MainActor
final class BreakControllerEnabledTests: XCTestCase {
  func testDisablingStoppedBreaksPersistsAcrossControllerInstances() {
    let store = InMemoryBreakStore(document: .standard)
    let controller = BreakController(store: store)

    controller.setEnabled(false)

    XCTAssertFalse(BreakController(store: store).isEnabled)
  }

  func testDisablingBreaksStopsAndPersistsAcrossControllerInstances() {
    let store = InMemoryBreakStore(document: .standard)
    let controller = BreakController(store: store)

    controller.startCycle()
    XCTAssertEqual(controller.snapshot.phase, .focusing)

    controller.setEnabled(false)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(controller.snapshot.phase, .stopped)

    let relaunchedController = BreakController(store: store)
    XCTAssertFalse(relaunchedController.isEnabled)

    relaunchedController.startCycle()
    relaunchedController.startBreakNow()
    XCTAssertEqual(relaunchedController.snapshot.phase, .stopped)
  }
}

private final class InMemoryBreakStore: BreakStore {
  private var document: BreakStateDocument

  init(document: BreakStateDocument) {
    self.document = document
  }

  func load() -> BreakStateDocument {
    document
  }

  func save(_ document: BreakStateDocument) throws {
    self.document = document
  }
}
