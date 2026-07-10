public enum DisplayCoordinatorMode: Equatable, Sendable {
  case idle
  case applied([String: DisplayAdjustment])
  case paused([String: DisplayAdjustment])
}

public final class DisplayCoordinator {
  public private(set) var displays: [DisplayDescriptor] = []
  public private(set) var mode: DisplayCoordinatorMode = .idle

  private let driver: any DisplayDriver
  private var baselines: [String: RGBTransferTable] = [:]
  private var activeAdjustments: [String: DisplayAdjustment] = [:]

  public init(driver: any DisplayDriver) {
    self.driver = driver
  }

  public func refreshDisplays() throws {
    let currentDisplays = try driver.enumerateDisplays()

    for display in currentDisplays where display.supportsGamma {
      if baselines[display.id.stableID] == nil {
        baselines[display.id.stableID] = try driver.captureTransferTable(for: display.id)
      }
    }

    displays = currentDisplays
  }

  public func apply(adjustment: DisplayAdjustment, to stableIDs: Set<String>) throws {
    try apply(adjustments: stableIDs.reduce(into: [:]) { $0[$1] = adjustment })
  }

  public func apply(adjustments: [String: DisplayAdjustment]) throws {
    if displays.isEmpty {
      try refreshDisplays()
    }

    let availableIDs = Set(displays.filter(\.supportsGamma).map(\.id.stableID))
    let applicableAdjustments = adjustments.filter { availableIDs.contains($0.key) }

    do {
      if case .applied = mode {
        let deselectedIDs = Set(activeAdjustments.keys).subtracting(applicableAdjustments.keys)
        try restore(stableIDs: deselectedIDs)
      }

      for display in displays where display.supportsGamma {
        guard let adjustment = applicableAdjustments[display.id.stableID] else {
          continue
        }
        guard let baseline = baselines[display.id.stableID] else {
          continue
        }

        let transformed = DisplayTransform.apply(adjustment: adjustment, to: baseline)
        try driver.apply(transformed, to: display.id)
      }
    } catch {
      try? restore(stableIDs: Set(activeAdjustments.keys).union(applicableAdjustments.keys))
      activeAdjustments.removeAll()
      mode = .idle
      throw error
    }

    activeAdjustments = applicableAdjustments
    mode = .applied(applicableAdjustments)
  }

  public func pause() throws {
    guard case .applied(let adjustments) = mode else {
      return
    }

    try restore(stableIDs: Set(activeAdjustments.keys))
    mode = .paused(adjustments)
  }

  public func resume() throws {
    guard case .paused(let adjustments) = mode else {
      return
    }

    try apply(adjustments: adjustments)
  }

  public func reset() throws {
    guard mode != .idle else {
      return
    }

    if case .applied = mode {
      try restore(stableIDs: Set(activeAdjustments.keys))
    }

    activeAdjustments.removeAll()
    mode = .idle
  }

  public func handleTopologyChange() throws {
    let previousMode = mode

    try refreshDisplays()

    if case .applied(let adjustments) = previousMode {
      try apply(adjustments: adjustments)
    }
  }

  private func restore(stableIDs: Set<String>) throws {
    for display in displays where stableIDs.contains(display.id.stableID) && display.supportsGamma {
      guard let baseline = baselines[display.id.stableID] else {
        continue
      }

      try driver.apply(baseline, to: display.id)
    }
  }
}
