import Foundation

public final class PreferencesRepository {
  private let defaults: UserDefaults
  private let legacyDefaults: UserDefaults?
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    defaults: UserDefaults = .standard,
    key: String = "app-preferences.v1",
    legacyDefaults: UserDefaults? = nil
  ) {
    self.defaults = defaults
    self.key = key
    self.legacyDefaults = legacyDefaults
  }

  public func load() -> AppPreferences {
    if let data = defaults.data(forKey: key),
      let preferences = try? decoder.decode(AppPreferences.self, from: data)
    {
      return preferences
    }

    guard
      let data = legacyDefaults?.data(forKey: key),
      let preferences = try? decoder.decode(AppPreferences.self, from: data)
    else {
      return .standard
    }

    try? save(preferences)
    return preferences
  }

  public func save(_ preferences: AppPreferences) throws {
    defaults.set(try encoder.encode(preferences), forKey: key)
  }
}
