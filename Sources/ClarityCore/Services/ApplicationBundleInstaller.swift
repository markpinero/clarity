import Foundation

public enum ApplicationBundleInstaller {
  public static func install(
    bundleAt source: URL,
    to destination: URL,
    using fileManager: FileManager = .default
  ) throws {
    let destinationDirectory = destination.deletingLastPathComponent()
    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

    let staging = destinationDirectory.appendingPathComponent(
      ".\(destination.lastPathComponent).install-\(UUID().uuidString)"
    )
    let backup = destinationDirectory.appendingPathComponent(
      ".\(destination.lastPathComponent).backup-\(UUID().uuidString)"
    )
    defer {
      try? fileManager.removeItem(at: staging)
      try? fileManager.removeItem(at: backup)
    }

    try fileManager.copyItem(at: source, to: staging)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: staging,
        backupItemName: backup.lastPathComponent
      )
    } else {
      try fileManager.moveItem(at: staging, to: destination)
    }
    try fileManager.removeItem(at: source)
  }
}
