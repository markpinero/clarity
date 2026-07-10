import ClarityBreaks
import Foundation
import XCTest

@testable import ClarityDiagnostics

final class ContextPermissionRequestHistoryTests: XCTestCase {
  func testRequestedPermissionSurvivesReinitialization() {
    let suiteName = "ContextPermissionRequestHistoryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initialHistory = ContextPermissionRequestHistory(defaults: defaults)
    initialHistory.markRequested(.accessibility)

    let relaunchedHistory = ContextPermissionRequestHistory(defaults: defaults)

    XCTAssertTrue(relaunchedHistory.contains(.accessibility))
    XCTAssertFalse(relaunchedHistory.contains(.screenRecording))
  }
}
