import Foundation

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
  private var ramps: [String: Ramp] = [:]
  private var displayedFactors: [String: ChannelFactors] = [:]

  private struct Ramp {
    var startFactors: ChannelFactors
    var targetFactors: ChannelFactors
    var startedAt: Date
    var timing: RampTiming
  }

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

  public func apply(
    adjustment: DisplayAdjustment,
    to stableIDs: Set<String>,
    timing: RampTiming = .instant,
    at now: Date = Date()
  ) throws {
    try apply(
      adjustments: stableIDs.reduce(into: [:]) { $0[$1] = adjustment },
      timing: timing,
      at: now
    )
  }

  public func apply(
    adjustments: [String: DisplayAdjustment],
    timing: RampTiming = .instant,
    at now: Date = Date()
  ) throws {
    if displays.isEmpty {
      try refreshDisplays()
    }

    let availableIDs = Set(displays.filter(\.supportsGamma).map(\.id.stableID))
    let applicableAdjustments = adjustments.filter { availableIDs.contains($0.key) }

    do {
      if case .applied = mode {
        let deselectedIDs = Set(activeAdjustments.keys).subtracting(applicableAdjustments.keys)
        try restore(stableIDs: deselectedIDs, timing: timing, at: now)
      }

      for display in displays where display.supportsGamma {
        guard let adjustment = applicableAdjustments[display.id.stableID] else {
          continue
        }
        guard let baseline = baselines[display.id.stableID] else {
          continue
        }

        try retarget(
          display: display,
          baseline: baseline,
          factors: DisplayTransform.factors(for: adjustment),
          timing: timing,
          at: now
        )
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

  public func pause(timing: RampTiming = .instant, at now: Date = Date()) throws {
    guard case .applied(let adjustments) = mode else {
      return
    }

    try restore(stableIDs: Set(activeAdjustments.keys), timing: timing, at: now)
    mode = .paused(adjustments)
  }

  public func resume(timing: RampTiming = .instant, at now: Date = Date()) throws {
    guard case .paused(let adjustments) = mode else {
      return
    }

    try apply(adjustments: adjustments, timing: timing, at: now)
  }

  public func reset(timing: RampTiming = .instant, at now: Date = Date()) throws {
    guard mode != .idle else {
      return
    }

    if case .applied = mode {
      try restore(stableIDs: Set(activeAdjustments.keys), timing: timing, at: now)
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

  private func restore(
    stableIDs: Set<String>,
    timing: RampTiming = .instant,
    at now: Date = Date()
  ) throws {
    for display in displays where stableIDs.contains(display.id.stableID) && display.supportsGamma
    {
      guard let baseline = baselines[display.id.stableID] else {
        continue
      }

      try retarget(
        display: display,
        baseline: baseline,
        factors: .identity,
        timing: timing,
        at: now
      )
    }
  }

  private func retarget(
    display: DisplayDescriptor,
    baseline: RGBTransferTable,
    factors: ChannelFactors,
    timing: RampTiming,
    at now: Date
  ) throws {
    let stableID = display.id.stableID
    if timing.duration == 0 {
      try driver.apply(DisplayTransform.apply(factors: factors, to: baseline), to: display.id)
      ramps[stableID] = nil
      displayedFactors[stableID] = factors
      return
    }

    let current = currentFactors(for: stableID, at: now)
    if ramps[stableID] == nil, current == factors {
      return
    }
    ramps[stableID] = Ramp(
      startFactors: current,
      targetFactors: factors,
      startedAt: now,
      timing: timing
    )
  }

  private func currentFactors(for stableID: String, at now: Date) -> ChannelFactors {
    if let ramp = ramps[stableID] {
      let progress = now.timeIntervalSince(ramp.startedAt) / ramp.timing.duration
      return ramp.startFactors.interpolated(
        to: ramp.targetFactors,
        progress: ramp.timing.eased(progress: progress)
      )
    }
    return displayedFactors[stableID] ?? .identity
  }
}
