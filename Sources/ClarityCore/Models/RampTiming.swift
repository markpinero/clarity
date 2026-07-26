import Foundation

public struct RampTiming: Equatable, Sendable {
  public enum Easing: Equatable, Sendable {
    case linear
    case smoothstep
  }

  public let duration: TimeInterval
  public let easing: Easing

  public init(duration: TimeInterval, easing: Easing) {
    self.duration = max(0, duration)
    self.easing = easing
  }

  public static let instant = RampTiming(duration: 0, easing: .linear)
  public static let manual = RampTiming(duration: 0.8, easing: .smoothstep)
  public static let schedule = RampTiming(duration: 30, easing: .linear)

  public func eased(progress: Double) -> Double {
    let clamped = min(max(progress, 0), 1)
    switch easing {
    case .linear:
      return clamped
    case .smoothstep:
      return clamped * clamped * (3 - 2 * clamped)
    }
  }
}
