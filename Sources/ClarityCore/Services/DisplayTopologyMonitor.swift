import CoreGraphics
import Foundation

public final class DisplayTopologyMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable () -> Void)?
  private var isRegistered = false

  public init() {}

  deinit {
    stop()
  }

  public func start(handler: @escaping @Sendable () -> Void) throws {
    lock.lock()
    defer { lock.unlock() }

    guard !isRegistered else {
      self.handler = handler
      return
    }

    self.handler = handler
    let context = Unmanaged.passUnretained(self).toOpaque()
    let result = CGDisplayRegisterReconfigurationCallback(Self.callback, context)
    guard result == .success else {
      self.handler = nil
      throw DisplayTopologyMonitorError.registrationFailed(result)
    }
    isRegistered = true
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }

    guard isRegistered else {
      handler = nil
      return
    }

    let context = Unmanaged.passUnretained(self).toOpaque()
    CGDisplayRemoveReconfigurationCallback(Self.callback, context)
    isRegistered = false
    handler = nil
  }

  private func deliverChange() {
    lock.lock()
    let handler = handler
    lock.unlock()
    handler?()
  }

  private static let callback: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else {
      return
    }

    let monitor = Unmanaged<DisplayTopologyMonitor>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
      monitor.deliverChange()
    }
  }
}

public enum DisplayTopologyMonitorError: Error, Equatable, LocalizedError {
  case registrationFailed(CGError)

  public var errorDescription: String? {
    switch self {
    case .registrationFailed(let error):
      "Could not monitor display reconfiguration (Core Graphics error \(error.rawValue))."
    }
  }
}
