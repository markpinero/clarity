public struct DisplayAdjustment: Codable, Equatable, Sendable {
  public let kelvin: Int
  public let brightness: Float

  public init(kelvin: Int, brightness: Float) {
    self.kelvin = kelvin
    self.brightness = brightness
  }

  public static func interpolated(
    from: DisplayAdjustment,
    to: DisplayAdjustment,
    progress: Double
  ) -> DisplayAdjustment {
    let clampedProgress = min(max(progress, 0), 1)
    let kelvin = Double(from.kelvin) + Double(to.kelvin - from.kelvin) * clampedProgress
    let brightness =
      Double(from.brightness) + Double(to.brightness - from.brightness) * clampedProgress

    return DisplayAdjustment(
      // Legacy Iris converts the interpolated float with cvttss2si, which truncates toward zero.
      kelvin: Int(kelvin),
      brightness: Float(brightness)
    )
  }
}
