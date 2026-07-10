import Foundation
import XCTest

@testable import ClarityCore

final class ApplicationInstallationLocationTests: XCTestCase {
  func testOnlySystemAndUserApplicationsDirectoriesCountAsInstalled() {
    XCTAssertTrue(
      ApplicationInstallationLocation.isInstalled(
        bundleURL: URL(fileURLWithPath: "/Applications/Clarity.app")
      )
    )
    XCTAssertTrue(
      ApplicationInstallationLocation.isInstalled(
        bundleURL: FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Applications/Clarity.app")
      )
    )
    XCTAssertFalse(
      ApplicationInstallationLocation.isInstalled(
        bundleURL: URL(
          fileURLWithPath: "/Users/markpinero/Projects/iris-alternative/dist/Clarity.app")
      )
    )
  }
}
