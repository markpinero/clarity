public enum ClarityProfile: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case health
  case reading
  case evening
  case sleep

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .health: "Health"
    case .reading: "Reading"
    case .evening: "Evening"
    case .sleep: "Sleep"
    }
  }

  public var adjustment: DisplayAdjustment {
    switch self {
    case .health: DisplayAdjustment(kelvin: 5_000, brightness: 1)
    case .reading: DisplayAdjustment(kelvin: 5_000, brightness: 0.95)
    case .evening: DisplayAdjustment(kelvin: 3_400, brightness: 0.8)
    case .sleep: DisplayAdjustment(kelvin: 2_700, brightness: 0.75)
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    if rawValue == "neutral" {
      self = .health
      return
    }
    guard let profile = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown Clarity profile: \(rawValue)"
      )
    }
    self = profile
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
