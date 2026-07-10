import Foundation
import XCTest

@testable import ClarityCore

final class ApplicationBundleInstallerTests: XCTestCase {
  func testInstallReplacesAnExistingApplicationAndRemovesTheSourceBundle() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClarityApplicationBundleInstallerTests.\(UUID().uuidString)")
    let source = root.appendingPathComponent("Downloads/Clarity.app")
    let destination = root.appendingPathComponent("Applications/Clarity.app")
    defer { try? FileManager.default.removeItem(at: root) }

    try writeBundle(at: source, marker: "new")
    try writeBundle(at: destination, marker: "old")

    try ApplicationBundleInstaller.install(bundleAt: source, to: destination)

    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker.txt")), "new")
  }

  private func writeBundle(at bundle: URL, marker: String) throws {
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try marker.write(
      to: bundle.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
  }
}
