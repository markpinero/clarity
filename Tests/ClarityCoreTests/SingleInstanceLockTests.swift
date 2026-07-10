import Foundation
import XCTest

@testable import ClarityCore

final class SingleInstanceLockTests: XCTestCase {
  func testSecondProcessCannotAcquireTheSameLockUntilTheFirstReleasesIt() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClaritySingleInstanceTests.\(UUID().uuidString)")
    let lockURL = directory.appendingPathComponent("Clarity.lock")
    defer { try? FileManager.default.removeItem(at: directory) }

    let primary = try XCTUnwrap(SingleInstanceLock.acquire(at: lockURL))
    XCTAssertNil(try SingleInstanceLock.acquire(at: lockURL))

    primary.release()
    XCTAssertNotNil(try SingleInstanceLock.acquire(at: lockURL))
  }
}
