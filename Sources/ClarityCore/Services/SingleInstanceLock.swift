import Darwin
import Foundation

public final class SingleInstanceLock: @unchecked Sendable {
  private var fileDescriptor: Int32?

  private init(fileDescriptor: Int32) {
    self.fileDescriptor = fileDescriptor
  }

  public static func acquire(bundleIdentifier: String) throws -> SingleInstanceLock? {
    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
    return try acquire(at: directory.appendingPathComponent("instance.lock"))
  }

  public static func acquire(at lockFileURL: URL) throws -> SingleInstanceLock? {
    let directory = lockFileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let fileDescriptor = Darwin.open(
      lockFileURL.path,
      O_CREAT | O_RDWR,
      mode_t(S_IRUSR | S_IWUSR)
    )
    guard fileDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      let error = errno
      Darwin.close(fileDescriptor)
      if error == EWOULDBLOCK { return nil }
      throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
    }

    return SingleInstanceLock(fileDescriptor: fileDescriptor)
  }

  public func release() {
    guard let fileDescriptor else { return }
    flock(fileDescriptor, LOCK_UN)
    Darwin.close(fileDescriptor)
    self.fileDescriptor = nil
  }

  deinit {
    release()
  }
}
