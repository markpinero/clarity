import Foundation

public struct RGBTransferTable: Equatable, Sendable {
  public let red: [Float]
  public let green: [Float]
  public let blue: [Float]

  public init(red: [Float], green: [Float], blue: [Float]) throws {
    guard !red.isEmpty, red.count == green.count, red.count == blue.count else {
      throw RGBTransferTableError.invalidChannelCounts
    }

    self.red = red
    self.green = green
    self.blue = blue
  }

  init(validatedRed red: [Float], green: [Float], blue: [Float]) {
    assert(!red.isEmpty && red.count == green.count && red.count == blue.count)
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public enum RGBTransferTableError: Error, Equatable {
  case invalidChannelCounts
}
