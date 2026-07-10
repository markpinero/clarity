public struct DisplayIdentifier: Hashable, Sendable {
  public let stableID: String
  public let runtimeID: UInt32

  public init(stableID: String, runtimeID: UInt32) {
    self.stableID = stableID
    self.runtimeID = runtimeID
  }
}

public struct DisplayDescriptor: Equatable, Identifiable, Sendable {
  public let id: DisplayIdentifier
  public let name: String
  public let isMain: Bool
  public let isBuiltin: Bool
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let gammaTableCapacity: Int

  public var supportsGamma: Bool {
    gammaTableCapacity > 0
  }

  public init(
    id: DisplayIdentifier,
    name: String,
    isMain: Bool,
    isBuiltin: Bool,
    pixelWidth: Int,
    pixelHeight: Int,
    gammaTableCapacity: Int
  ) {
    self.id = id
    self.name = name
    self.isMain = isMain
    self.isBuiltin = isBuiltin
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.gammaTableCapacity = gammaTableCapacity
  }
}
