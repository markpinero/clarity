import Foundation

public enum BreakEvent: Equatable, Sendable {
  case start(Date)
  case startBreak(Date)
  case stop
  case tick(Date)
  case pause(Date)
  case resume(Date)
  case contextChanged(
    Date,
    reasons: Set<BreakPauseReason>,
    resetFocusAfterIdle: Bool = false
  )
  case snooze(Date)
  case skip(Date)
  case reset
}

public enum BreakEffect: Equatable, Sendable {
  case persist
  case presentCountdown
  case presentBreak
  case dismissBreak
}

public enum BreakReducer {
  @discardableResult
  public static func reduce(
    _ state: inout BreakSnapshot,
    event: BreakEvent,
    configuration: BreakConfiguration
  ) -> [BreakEffect] {
    switch event {
    case .start(let now):
      let pauseReasons = state.pauseReasons
      startFocus(&state, at: now, duration: configuration.focusDuration)
      state.pauseReasons = []
      return [.persist, .dismissBreak]
        + reconcilePauseReasons(&state, reasons: pauseReasons, at: now)

    case .startBreak(let now):
      startManualBreak(&state, at: now, duration: configuration.shortBreakDuration)
      return [.persist, .presentBreak]

    case .stop, .reset:
      state = .stopped
      return [.persist, .dismissBreak]

    case .tick(let now):
      return tick(&state, now: now, configuration: configuration)

    case .pause(let now):
      return reconcilePauseReasons(
        &state,
        reasons: state.pauseReasons.union([.manual]),
        at: now
      )

    case .resume(let now):
      return reconcilePauseReasons(
        &state,
        reasons: state.pauseReasons.subtracting([.manual]),
        at: now
      )

    case .contextChanged(let now, let reasons, let resetFocusAfterIdle):
      let manualPause = state.pauseReasons.contains(.manual)
      let combinedReasons = reasons.union(manualPause ? [.manual] : [])
      if resetFocusAfterIdle, state.phase != .stopped {
        startFocus(&state, at: now, duration: configuration.focusDuration)
        state.pauseReasons = []
        return [.persist, .dismissBreak]
          + reconcilePauseReasons(&state, reasons: combinedReasons, at: now)
      }
      return reconcilePauseReasons(&state, reasons: combinedReasons, at: now)

    case .snooze(let now):
      guard [.countdown, .breaking].contains(state.phase) else { return [] }
      state.snoozeCount += 1
      startFocus(&state, at: now, duration: configuration.snoozeDuration)
      return [.persist, .dismissBreak]

    case .skip(let now):
      guard [.countdown, .breaking].contains(state.phase) else { return [] }
      if state.phase == .countdown { state.completedFocusIntervals += 1 }
      startFocus(&state, at: now, duration: configuration.focusDuration)
      return [.persist, .dismissBreak]
    }
  }

  @discardableResult
  public static func recover(
    _ state: inout BreakSnapshot,
    now: Date,
    configuration: BreakConfiguration
  ) -> [BreakEffect] {
    reduce(&state, event: .tick(now), configuration: configuration)
  }

  private static func tick(
    _ state: inout BreakSnapshot,
    now: Date,
    configuration: BreakConfiguration
  ) -> [BreakEffect] {
    guard let deadline = state.phaseDeadline else { return [] }

    switch state.phase {
    case .focusing:
      if now >= deadline {
        beginBreak(&state, at: now, configuration: configuration)
        return [.persist, .presentBreak]
      }
      if now >= deadline.addingTimeInterval(-configuration.countdownDuration) {
        state.phase = .countdown
        state.breakKind = nextBreakKind(for: state, configuration: configuration)
        return [.persist, .presentCountdown]
      }
      return []

    case .countdown:
      guard now >= deadline else { return [] }
      beginBreak(&state, at: now, configuration: configuration)
      return [.persist, .presentBreak]

    case .breaking:
      guard now >= deadline else { return [] }
      startFocus(&state, at: now, duration: configuration.focusDuration)
      return [.persist, .dismissBreak]

    case .stopped, .paused:
      return []
    }
  }

  private static func beginBreak(
    _ state: inout BreakSnapshot,
    at now: Date,
    configuration: BreakConfiguration
  ) {
    state.completedFocusIntervals += 1
    let kind = nextBreakKind(
      afterCompleting: state.completedFocusIntervals, configuration: configuration)
    state.phase = .breaking
    state.breakKind = kind
    state.phaseDeadline = now.addingTimeInterval(
      kind == .long ? configuration.longBreakDuration : configuration.shortBreakDuration
    )
    state.pausedPhase = nil
    state.pausedRemaining = nil
  }

  private static func startManualBreak(
    _ state: inout BreakSnapshot,
    at now: Date,
    duration: TimeInterval
  ) {
    state.phase = .breaking
    state.phaseDeadline = now.addingTimeInterval(duration)
    state.pausedPhase = nil
    state.pausedRemaining = nil
    state.breakKind = .short
    state.pauseReasons = []
  }

  private static func reconcilePauseReasons(
    _ state: inout BreakSnapshot,
    reasons: Set<BreakPauseReason>,
    at now: Date
  ) -> [BreakEffect] {
    let previousReasons = state.pauseReasons
    guard previousReasons != reasons else { return [] }
    state.pauseReasons = reasons

    guard state.phase != .stopped else { return [.persist] }

    if previousReasons.isEmpty, !reasons.isEmpty, state.phase != .paused {
      let previousPhase = state.phase
      state.pausedPhase = previousPhase
      state.pausedRemaining = state.phaseDeadline.map {
        max(0, $0.timeIntervalSince(now))
      }
      state.phase = .paused
      state.phaseDeadline = nil
      return [.countdown, .breaking].contains(previousPhase)
        ? [.persist, .dismissBreak] : [.persist]
    }

    if reasons.isEmpty, state.phase == .paused {
      let restoredPhase = state.pausedPhase ?? .focusing
      let remaining = max(0, state.pausedRemaining ?? 0)
      state.phase = restoredPhase
      state.phaseDeadline = now.addingTimeInterval(remaining)
      state.pausedPhase = nil
      state.pausedRemaining = nil
      switch restoredPhase {
      case .countdown:
        return [.persist, .presentCountdown]
      case .breaking:
        return [.persist, .presentBreak]
      case .stopped, .focusing, .paused:
        return [.persist]
      }
    }

    return [.persist]
  }

  private static func startFocus(
    _ state: inout BreakSnapshot,
    at now: Date,
    duration: TimeInterval
  ) {
    state.phase = .focusing
    state.phaseDeadline = now.addingTimeInterval(duration)
    state.pausedPhase = nil
    state.pausedRemaining = nil
    state.breakKind = nil
  }

  private static func nextBreakKind(
    for state: BreakSnapshot,
    configuration: BreakConfiguration
  ) -> BreakKind {
    nextBreakKind(
      afterCompleting: state.completedFocusIntervals + 1,
      configuration: configuration
    )
  }

  private static func nextBreakKind(
    afterCompleting interval: Int,
    configuration: BreakConfiguration
  ) -> BreakKind {
    interval.isMultiple(of: configuration.longBreakEvery) ? .long : .short
  }
}
