public struct GeographicCoordinate: Codable, Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = min(max(latitude, -90), 90)
    let remainder = (longitude + 180).truncatingRemainder(dividingBy: 360)
    self.longitude = (remainder >= 0 ? remainder : remainder + 360) - 180
  }

  public func coarsened(step: Double = 0.1) -> GeographicCoordinate {
    guard step > 0 else { return self }
    let scale = 1 / step
    return GeographicCoordinate(
      latitude: (latitude * scale).rounded() / scale,
      longitude: (longitude * scale).rounded() / scale
    )
  }
}

public enum SolarLocationSource: String, CaseIterable, Codable, Identifiable, Sendable {
  case automatic
  case manual

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .automatic: "Use My Location"
    case .manual: "Enter Manually"
    }
  }
}

public enum ResolvedSolarLocationSource: String, Codable, Equatable, Sendable {
  case automatic
  case manual
  case manualFallback
}

public struct ResolvedSolarLocation: Equatable, Sendable {
  public let coordinate: GeographicCoordinate
  public let source: ResolvedSolarLocationSource

  public init(coordinate: GeographicCoordinate, source: ResolvedSolarLocationSource) {
    self.coordinate = coordinate
    self.source = source
  }
}

public struct SolarLocationSettings: Codable, Equatable, Sendable {
  public var source: SolarLocationSource
  public var automaticCoordinate: GeographicCoordinate?
  public var manualCoordinate: GeographicCoordinate?

  public init(
    source: SolarLocationSource,
    automaticCoordinate: GeographicCoordinate? = nil,
    manualCoordinate: GeographicCoordinate? = nil
  ) {
    self.source = source
    self.automaticCoordinate = automaticCoordinate
    self.manualCoordinate = manualCoordinate
  }

  public static let standard = SolarLocationSettings(source: .automatic)

  public var resolvedLocation: ResolvedSolarLocation? {
    switch source {
    case .automatic:
      if let automaticCoordinate {
        return ResolvedSolarLocation(
          coordinate: automaticCoordinate.coarsened(),
          source: .automatic
        )
      }
      if let manualCoordinate {
        return ResolvedSolarLocation(coordinate: manualCoordinate, source: .manualFallback)
      }
      return nil
    case .manual:
      return manualCoordinate.map {
        ResolvedSolarLocation(coordinate: $0, source: .manual)
      }
    }
  }
}
