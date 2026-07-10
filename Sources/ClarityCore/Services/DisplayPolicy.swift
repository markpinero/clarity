import Foundation

public enum DisplayPolicy {
  public static func resolve(
    preferences: AppPreferences,
    atMinute minute: Double,
    context: AutomationContext = .empty
  ) -> DisplayPolicyDecision {
    guard preferences.isEnabled else {
      return DisplayPolicyDecision(adjustment: nil, source: .disabled)
    }

    guard !preferences.isPaused else {
      return DisplayPolicyDecision(adjustment: nil, source: .paused)
    }

    if let automation = resolveAutomation(preferences: preferences, context: context) {
      return automation
    }

    switch preferences.controlMode {
    case .manual:
      return DisplayPolicyDecision(
        adjustment: preferences.selectedProfile.adjustment,
        source: .manual(profile: preferences.selectedProfile)
      )
    case .automatic:
      return resolveAutomatic(preferences: preferences, atMinute: minute)
    }
  }

  public static func resolve(
    preferences: AppPreferences,
    at date: Date,
    calendar: Calendar = .current,
    context: AutomationContext = .empty
  ) -> DisplayPolicyDecision {
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    let minute =
      Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
      + Double(components.second ?? 0) / 60

    guard preferences.isEnabled else {
      return DisplayPolicyDecision(adjustment: nil, source: .disabled)
    }
    guard !preferences.isPaused else {
      return DisplayPolicyDecision(adjustment: nil, source: .paused)
    }
    if let automation = resolveAutomation(preferences: preferences, context: context) {
      return automation
    }
    guard preferences.controlMode == .automatic else {
      return DisplayPolicyDecision(
        adjustment: preferences.selectedProfile.adjustment,
        source: .manual(profile: preferences.selectedProfile)
      )
    }

    guard preferences.automaticScheduleKind == .solar else {
      return resolveClock(preferences: preferences, atMinute: minute)
    }
    guard let location = preferences.solarLocation.resolvedLocation else {
      return resolveClock(
        preferences: preferences,
        atMinute: minute,
        basis: .clockFallback(.locationUnavailable)
      )
    }
    guard
      let events = SolarCalculator.events(
        on: date,
        coordinate: location.coordinate,
        calendar: calendar
      )
    else {
      return resolveClock(
        preferences: preferences,
        atMinute: minute,
        basis: .clockFallback(.solarEventsUnavailable)
      )
    }

    let scheduled = preferences.solarSchedule.resolve(
      atMinute: minute,
      sunriseMinute: events.sunriseMinute,
      sunsetMinute: events.sunsetMinute,
      moonPhase: MoonCalculator.illuminatedFraction(at: date)
    )
    return DisplayPolicyDecision(
      adjustment: scheduled.adjustment,
      source: .automatic(phase: scheduled.phase),
      scheduleBasis: .solar(events, location.source)
    )
  }

  public static func targetAdjustments(
    globalAdjustment: DisplayAdjustment,
    stableIDs: Set<String>,
    displaySettings: [String: DisplaySettings]
  ) -> [String: DisplayAdjustment] {
    stableIDs.reduce(into: [:]) { targets, stableID in
      let settings = displaySettings[stableID] ?? .standard
      guard settings.isEnabled else { return }
      targets[stableID] = settings.profileOverride?.adjustment ?? globalAdjustment
    }
  }

  private static func resolveAutomatic(
    preferences: AppPreferences,
    atMinute minute: Double
  ) -> DisplayPolicyDecision {
    guard preferences.automaticScheduleKind == .solar else {
      return resolveClock(preferences: preferences, atMinute: minute)
    }
    guard let location = preferences.solarLocation.resolvedLocation else {
      return resolveClock(
        preferences: preferences,
        atMinute: minute,
        basis: .clockFallback(.locationUnavailable)
      )
    }
    let date = Date.now
    guard let events = SolarCalculator.events(on: date, coordinate: location.coordinate) else {
      return resolveClock(
        preferences: preferences,
        atMinute: minute,
        basis: .clockFallback(.solarEventsUnavailable)
      )
    }
    let scheduled = preferences.solarSchedule.resolve(
      atMinute: minute,
      sunriseMinute: events.sunriseMinute,
      sunsetMinute: events.sunsetMinute,
      moonPhase: MoonCalculator.illuminatedFraction(at: date)
    )
    return DisplayPolicyDecision(
      adjustment: scheduled.adjustment,
      source: .automatic(phase: scheduled.phase),
      scheduleBasis: .solar(events, location.source)
    )
  }

  private static func resolveAutomation(
    preferences: AppPreferences,
    context: AutomationContext
  ) -> DisplayPolicyDecision? {
    if preferences.pauseInFullscreen, context.isActiveApplicationFullscreen {
      return DisplayPolicyDecision(
        adjustment: nil,
        source: .automationPaused(.fullscreen)
      )
    }

    guard
      let bundleIdentifier = context.activeApplicationBundleIdentifier,
      let rule = preferences.activeAppRules.first(where: {
        $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
      })
    else {
      return nil
    }

    switch rule.action {
    case .pause:
      return DisplayPolicyDecision(
        adjustment: nil,
        source: .automationPaused(.activeApplication(bundleIdentifier: bundleIdentifier))
      )
    case .profile(let profile):
      return DisplayPolicyDecision(
        adjustment: profile.adjustment,
        source: .automationProfile(profile, bundleIdentifier: bundleIdentifier)
      )
    }
  }

  private static func resolveClock(
    preferences: AppPreferences,
    atMinute minute: Double,
    basis: AutomaticScheduleBasis = .clock
  ) -> DisplayPolicyDecision {
    let scheduled = preferences.schedule.resolve(atMinute: minute)
    return DisplayPolicyDecision(
      adjustment: scheduled.adjustment,
      source: .automatic(phase: scheduled.phase),
      scheduleBasis: basis
    )
  }
}

public struct DisplayPolicyDecision: Equatable, Sendable {
  public let adjustment: DisplayAdjustment?
  public let source: DisplayPolicySource
  public let scheduleBasis: AutomaticScheduleBasis?

  public init(
    adjustment: DisplayAdjustment?,
    source: DisplayPolicySource,
    scheduleBasis: AutomaticScheduleBasis? = nil
  ) {
    self.adjustment = adjustment
    self.source = source
    self.scheduleBasis = scheduleBasis
  }
}

public enum DisplayPolicySource: Equatable, Sendable {
  case disabled
  case paused
  case manual(profile: ClarityProfile)
  case automatic(phase: SchedulePhase)
  case automationPaused(AutomationPauseReason)
  case automationProfile(ClarityProfile, bundleIdentifier: String)
}

public enum AutomaticScheduleBasis: Equatable, Sendable {
  case clock
  case solar(SolarEvents, ResolvedSolarLocationSource)
  case clockFallback(AutomaticScheduleFallbackReason)
}

public enum AutomaticScheduleFallbackReason: Equatable, Sendable {
  case locationUnavailable
  case solarEventsUnavailable
}
