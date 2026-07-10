import ColorSync
import CoreGraphics
import Foundation

public final class CoreGraphicsDisplayDriver: DisplayDriver {
  public init() {}

  public func enumerateDisplays() throws -> [DisplayDescriptor] {
    var displayCount: UInt32 = 0
    var result = CGGetOnlineDisplayList(0, nil, &displayCount)
    guard result == .success else {
      throw CoreGraphicsDisplayDriverError.enumerationFailed(result)
    }

    var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
    result = displayIDs.withUnsafeMutableBufferPointer { buffer in
      CGGetOnlineDisplayList(displayCount, buffer.baseAddress, &displayCount)
    }
    guard result == .success else {
      throw CoreGraphicsDisplayDriverError.enumerationFailed(result)
    }

    return displayIDs.prefix(Int(displayCount)).enumerated().map { index, runtimeID in
      DisplayDescriptor(
        id: DisplayIdentifier(
          stableID: stableIdentifier(for: runtimeID),
          runtimeID: runtimeID
        ),
        name: displayName(for: runtimeID, index: index),
        isMain: CGDisplayIsMain(runtimeID) != 0,
        isBuiltin: CGDisplayIsBuiltin(runtimeID) != 0,
        pixelWidth: CGDisplayPixelsWide(runtimeID),
        pixelHeight: CGDisplayPixelsHigh(runtimeID),
        gammaTableCapacity: Int(CGDisplayGammaTableCapacity(runtimeID))
      )
    }
  }

  public func captureTransferTable(for display: DisplayIdentifier) throws -> RGBTransferTable {
    let capacity = CGDisplayGammaTableCapacity(display.runtimeID)
    guard capacity > 0 else {
      throw CoreGraphicsDisplayDriverError.gammaUnsupported(display.stableID)
    }

    var red = Array(repeating: CGGammaValue(), count: Int(capacity))
    var green = Array(repeating: CGGammaValue(), count: Int(capacity))
    var blue = Array(repeating: CGGammaValue(), count: Int(capacity))
    var sampleCount: UInt32 = 0

    let result = red.withUnsafeMutableBufferPointer { redBuffer in
      green.withUnsafeMutableBufferPointer { greenBuffer in
        blue.withUnsafeMutableBufferPointer { blueBuffer in
          CGGetDisplayTransferByTable(
            display.runtimeID,
            capacity,
            redBuffer.baseAddress,
            greenBuffer.baseAddress,
            blueBuffer.baseAddress,
            &sampleCount
          )
        }
      }
    }

    guard result == .success else {
      throw CoreGraphicsDisplayDriverError.captureFailed(display.stableID, result)
    }
    guard sampleCount > 0 else {
      throw CoreGraphicsDisplayDriverError.emptyTransferTable(display.stableID)
    }

    return try RGBTransferTable(
      red: Array(red.prefix(Int(sampleCount))),
      green: Array(green.prefix(Int(sampleCount))),
      blue: Array(blue.prefix(Int(sampleCount)))
    )
  }

  public func apply(_ table: RGBTransferTable, to display: DisplayIdentifier) throws {
    let sampleCount = UInt32(table.red.count)
    let result = table.red.withUnsafeBufferPointer { redBuffer in
      table.green.withUnsafeBufferPointer { greenBuffer in
        table.blue.withUnsafeBufferPointer { blueBuffer in
          CGSetDisplayTransferByTable(
            display.runtimeID,
            sampleCount,
            redBuffer.baseAddress,
            greenBuffer.baseAddress,
            blueBuffer.baseAddress
          )
        }
      }
    }

    guard result == .success else {
      throw CoreGraphicsDisplayDriverError.applyFailed(display.stableID, result)
    }
  }

  private func stableIdentifier(for runtimeID: CGDirectDisplayID) -> String {
    guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(runtimeID) else {
      return "runtime-\(runtimeID)"
    }

    let uuid = unmanagedUUID.takeRetainedValue()
    return (CFUUIDCreateString(nil, uuid) as String?) ?? "runtime-\(runtimeID)"
  }

  private func displayName(for runtimeID: CGDirectDisplayID, index: Int) -> String {
    if CGDisplayIsBuiltin(runtimeID) != 0 {
      return "Built-in Display"
    }
    if CGDisplayIsMain(runtimeID) != 0 {
      return "Main Display"
    }
    return "External Display \(index + 1)"
  }
}

public enum CoreGraphicsDisplayDriverError: Error, Equatable, LocalizedError {
  case enumerationFailed(CGError)
  case gammaUnsupported(String)
  case captureFailed(String, CGError)
  case emptyTransferTable(String)
  case applyFailed(String, CGError)

  public var errorDescription: String? {
    switch self {
    case .enumerationFailed(let error):
      "Could not enumerate online displays (Core Graphics error \(error.rawValue))."
    case .gammaUnsupported(let stableID):
      "Display \(stableID) does not expose a gamma transfer table."
    case .captureFailed(let stableID, let error):
      "Could not capture the transfer table for \(stableID) (Core Graphics error \(error.rawValue))."
    case .emptyTransferTable(let stableID):
      "Display \(stableID) returned an empty gamma transfer table."
    case .applyFailed(let stableID, let error):
      "Could not apply the transfer table to \(stableID) (Core Graphics error \(error.rawValue))."
    }
  }
}
