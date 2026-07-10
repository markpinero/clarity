import XCTest

@testable import ClarityBreaks

final class ContextPermissionPlanTests: XCTestCase {
  func testUndeterminedPermissionRequestsOnceAndDeniedPermissionsOpenSettings() {
    XCTAssertEqual(
      ContextPermissionPlan.action(for: .notDetermined),
      .requestSystemPermission
    )
    XCTAssertEqual(
      ContextPermissionPlan.action(for: .denied),
      .openSystemSettings
    )
    XCTAssertEqual(ContextPermissionPlan.action(for: .granted), .none)
  }
}
