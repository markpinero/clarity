import Foundation

public enum SettingsDocument {
  public static let currentFormatVersion = 1

  public static func encode(_ preferences: AppPreferences) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(
      Payload(formatVersion: currentFormatVersion, preferences: preferences)
    )
  }

  public static func decode(_ data: Data) throws -> AppPreferences {
    let decoder = JSONDecoder()
    let envelope = try decoder.decode(VersionEnvelope.self, from: data)
    guard envelope.formatVersion == currentFormatVersion else {
      throw SettingsDocumentError.unsupportedVersion(envelope.formatVersion)
    }
    return try decoder.decode(Payload.self, from: data).preferences
  }

  private struct VersionEnvelope: Decodable {
    let formatVersion: Int
  }

  private struct Payload: Codable {
    let formatVersion: Int
    let preferences: AppPreferences
  }
}

public enum SettingsDocumentError: Error, Equatable, LocalizedError {
  case unsupportedVersion(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      "Settings format version \(version) is not supported."
    }
  }
}
