import Foundation

public struct ChannelFactors: Equatable, Sendable {
  public let red: Float
  public let green: Float
  public let blue: Float

  public init(red: Float, green: Float, blue: Float) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public static let identity = ChannelFactors(red: 1, green: 1, blue: 1)

  public func scaled(by brightness: Float) -> ChannelFactors {
    let clamped = min(max(brightness, 0), 1)
    return ChannelFactors(
      red: red * clamped,
      green: green * clamped,
      blue: blue * clamped
    )
  }

  public func interpolated(to other: ChannelFactors, progress: Double) -> ChannelFactors {
    let clamped = Float(min(max(progress, 0), 1))
    return ChannelFactors(
      red: red + (other.red - red) * clamped,
      green: green + (other.green - green) * clamped,
      blue: blue + (other.blue - blue) * clamped
    )
  }
}
