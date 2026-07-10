import Foundation

public struct BreakStateDocument: Codable, Equatable, Sendable {
  public var configuration: BreakConfiguration
  public var snapshot: BreakSnapshot

  public init(configuration: BreakConfiguration, snapshot: BreakSnapshot) {
    self.configuration = configuration
    self.snapshot = snapshot
  }

  public static let standard = BreakStateDocument(
    configuration: .standard,
    snapshot: .stopped
  )
}

public protocol BreakStore {
  func load() -> BreakStateDocument
  func save(_ document: BreakStateDocument) throws
}

public final class UserDefaultsBreakStore: BreakStore {
  private let defaults: UserDefaults
  private let legacyDefaults: UserDefaults?
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    defaults: UserDefaults = .standard,
    key: String = "break-state.v1",
    legacyDefaults: UserDefaults? = nil
  ) {
    self.defaults = defaults
    self.key = key
    self.legacyDefaults = legacyDefaults
  }

  public func load() -> BreakStateDocument {
    if let data = defaults.data(forKey: key),
      let document = try? decoder.decode(BreakStateDocument.self, from: data)
    {
      return document
    }

    guard
      let data = legacyDefaults?.data(forKey: key),
      let document = try? decoder.decode(BreakStateDocument.self, from: data)
    else {
      return .standard
    }

    try? save(document)
    return document
  }

  public func save(_ document: BreakStateDocument) throws {
    defaults.set(try encoder.encode(document), forKey: key)
  }
}
