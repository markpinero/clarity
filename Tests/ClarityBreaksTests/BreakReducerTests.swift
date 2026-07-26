import XCTest

@testable import ClarityBreaks

final class BreakReducerTests: XCTestCase {
  private let configuration = BreakConfiguration(
    focusDuration: 20,
    shortBreakDuration: 5,
    longBreakDuration: 12,
    longBreakEvery: 4,
    countdownDuration: 3,
    snoozeDuration: 7
  )

  func testPreBreakNotificationIsFixedToFinalTenSeconds() {
    let requestedLongCountdown = BreakConfiguration(
      focusDuration: 20,
      shortBreakDuration: 5,
      longBreakDuration: 12,
      longBreakEvery: 4,
      countdownDuration: 15,
      snoozeDuration: 7
    )
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 900)
    BreakReducer.reduce(&state, event: .start(start), configuration: requestedLongCountdown)

    let earlyEffects = BreakReducer.reduce(
      &state,
      event: .tick(start.addingTimeInterval(9)),
      configuration: requestedLongCountdown
    )
    XCTAssertEqual(state.phase, .focusing)
    XCTAssertFalse(earlyEffects.contains(.presentCountdown))

    let countdownEffects = BreakReducer.reduce(
      &state,
      event: .tick(start.addingTimeInterval(10)),
      configuration: requestedLongCountdown
    )
    XCTAssertEqual(requestedLongCountdown.countdownDuration, 10)
    XCTAssertEqual(state.phase, .countdown)
    XCTAssertTrue(countdownEffects.contains(.presentCountdown))
  }

  func testManualStartImmediatelyPresentsAShortBreakWithoutCompletingFocus() throws {
    var state = BreakSnapshot.stopped
    let now = Date(timeIntervalSince1970: 950)

    let effects = BreakReducer.reduce(
      &state,
      event: .startBreak(now),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertEqual(state.breakKind, .short)
    XCTAssertEqual(state.phaseDeadline, now.addingTimeInterval(configuration.shortBreakDuration))
    XCTAssertEqual(state.completedFocusIntervals, 0)
    XCTAssertTrue(effects.contains(.presentBreak))
  }

  func testManualStartCanBeginABreakEarlyDuringFocus() throws {
    let focusStart = Date(timeIntervalSince1970: 975)
    let manualStart = focusStart.addingTimeInterval(8)
    var state = BreakSnapshot.stopped
    BreakReducer.reduce(&state, event: .start(focusStart), configuration: configuration)

    let effects = BreakReducer.reduce(
      &state,
      event: .startBreak(manualStart),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertEqual(
      state.phaseDeadline, manualStart.addingTimeInterval(configuration.shortBreakDuration))
    XCTAssertEqual(state.completedFocusIntervals, 0)
    XCTAssertTrue(effects.contains(.presentBreak))
  }

  func testManualStartOverridesAnAutomaticPause() throws {
    let focusStart = Date(timeIntervalSince1970: 990)
    let manualStart = focusStart.addingTimeInterval(8)
    var state = BreakSnapshot.stopped
    BreakReducer.reduce(&state, event: .start(focusStart), configuration: configuration)
    BreakReducer.reduce(
      &state,
      event: .contextChanged(manualStart, reasons: [.screenSharing]),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .paused)

    let effects = BreakReducer.reduce(
      &state,
      event: .startBreak(manualStart),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertEqual(state.pauseReasons, [])
    XCTAssertEqual(
      state.phaseDeadline,
      manualStart.addingTimeInterval(configuration.shortBreakDuration)
    )
    XCTAssertTrue(effects.contains(.presentBreak))
  }

  func testAutomaticPauseDoesNotDismissAnActiveManualBreak() throws {
    let breakStart = Date(timeIntervalSince1970: 995)
    var state = BreakSnapshot.stopped
    BreakReducer.reduce(&state, event: .startBreak(breakStart), configuration: configuration)

    let effects = BreakReducer.reduce(
      &state,
      event: .contextChanged(
        breakStart.addingTimeInterval(2),
        reasons: [.screenSharing]
      ),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertEqual(
      state.phaseDeadline,
      breakStart.addingTimeInterval(configuration.shortBreakDuration)
    )
    XCTAssertFalse(effects.contains(.dismissBreak))
  }

  func testEveryFourthCompletedFocusIntervalProducesALongBreak() {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 1_000)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)

    for interval in 1...4 {
      let focusDeadline = try! XCTUnwrap(state.phaseDeadline)
      BreakReducer.reduce(
        &state,
        event: .tick(focusDeadline),
        configuration: configuration
      )

      XCTAssertEqual(state.phase, .breaking)
      XCTAssertEqual(state.breakKind, interval == 4 ? .long : .short)

      let breakDeadline = try! XCTUnwrap(state.phaseDeadline)
      BreakReducer.reduce(
        &state,
        event: .tick(breakDeadline),
        configuration: configuration
      )
      XCTAssertEqual(state.phase, .focusing)
    }
  }

  func testCountdownCanBeSnoozedIntoANewFocusDeadline() throws {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 2_000)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)
    BreakReducer.reduce(
      &state,
      event: .tick(start.addingTimeInterval(17)),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .countdown)
    XCTAssertEqual(state.breakKind, .short)

    let snoozeTime = start.addingTimeInterval(18)
    let effects = BreakReducer.reduce(
      &state,
      event: .snooze(snoozeTime),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .focusing)
    XCTAssertEqual(state.phaseDeadline, snoozeTime.addingTimeInterval(7))
    XCTAssertEqual(state.snoozeCount, 1)
    XCTAssertTrue(effects.contains(.dismissBreak))
  }

  func testCountdownOverlayTracksPauseAndResume() {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 2_500)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)

    let countdownEffects = BreakReducer.reduce(
      &state,
      event: .tick(start.addingTimeInterval(17)),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .countdown)
    XCTAssertTrue(countdownEffects.contains(.presentCountdown))

    let pauseEffects = BreakReducer.reduce(
      &state,
      event: .pause(start.addingTimeInterval(18)),
      configuration: configuration
    )
    XCTAssertEqual(state.pausedPhase, .countdown)
    XCTAssertTrue(pauseEffects.contains(.dismissBreak))

    let resumeEffects = BreakReducer.reduce(
      &state,
      event: .resume(start.addingTimeInterval(19)),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .countdown)
    XCTAssertTrue(resumeEffects.contains(.presentCountdown))
  }

  func testPauseAndResumePreserveRemainingTime() throws {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 3_000)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)
    BreakReducer.reduce(
      &state,
      event: .pause(start.addingTimeInterval(8)),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .paused)
    XCTAssertEqual(state.pausedPhase, .focusing)
    XCTAssertEqual(state.pausedRemaining, 12)

    let resumeTime = start.addingTimeInterval(100)
    BreakReducer.reduce(&state, event: .resume(resumeTime), configuration: configuration)
    XCTAssertEqual(state.phase, .focusing)
    XCTAssertEqual(state.phaseDeadline, resumeTime.addingTimeInterval(12))
  }

  func testAutomaticPauseReasonsAccumulateAndResumeOnlyAfterTheLastReasonClears() throws {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 4_000)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)

    BreakReducer.reduce(
      &state,
      event: .contextChanged(
        start.addingTimeInterval(8),
        reasons: [.calendarMeeting]
      ),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .paused)
    XCTAssertEqual(state.pausedRemaining, 12)
    XCTAssertEqual(state.pauseReasons, [.calendarMeeting])

    BreakReducer.reduce(
      &state,
      event: .contextChanged(
        start.addingTimeInterval(9),
        reasons: [.calendarMeeting, .videoPlayback]
      ),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .paused)
    XCTAssertEqual(state.pauseReasons, [.calendarMeeting, .videoPlayback])

    BreakReducer.reduce(
      &state,
      event: .contextChanged(
        start.addingTimeInterval(10),
        reasons: [.videoPlayback]
      ),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .paused)

    let resumed = start.addingTimeInterval(11)
    BreakReducer.reduce(
      &state,
      event: .contextChanged(resumed, reasons: []),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .focusing)
    XCTAssertEqual(state.phaseDeadline, resumed.addingTimeInterval(12))
  }

  func testReturningFromQualifiedIdleStartsAFreshFocusSession() throws {
    var state = BreakSnapshot.stopped
    let start = Date(timeIntervalSince1970: 4_500)
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)
    BreakReducer.reduce(
      &state,
      event: .contextChanged(
        start.addingTimeInterval(10),
        reasons: [.idle]
      ),
      configuration: configuration
    )

    let returned = start.addingTimeInterval(100)
    BreakReducer.reduce(
      &state,
      event: .contextChanged(
        returned,
        reasons: [],
        resetFocusAfterIdle: true
      ),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .focusing)
    XCTAssertEqual(state.phaseDeadline, returned.addingTimeInterval(20))
    XCTAssertEqual(state.pauseReasons, [])
    XCTAssertEqual(state.completedFocusIntervals, 0)
  }

  func testReturningFromQualifiedIdleDoesNotCancelAManuallyStartedBreak() throws {
    let breakStart = Date(timeIntervalSince1970: 4_800)
    var state = BreakSnapshot.stopped
    BreakReducer.reduce(&state, event: .startBreak(breakStart), configuration: configuration)

    let effects = BreakReducer.reduce(
      &state,
      event: .contextChanged(
        breakStart.addingTimeInterval(1),
        reasons: [],
        resetFocusAfterIdle: true
      ),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertEqual(
      state.phaseDeadline,
      breakStart.addingTimeInterval(configuration.shortBreakDuration)
    )
    XCTAssertFalse(effects.contains(.dismissBreak))
  }

  func testRecoveryAdvancesExpiredDeadlinesWithoutReplayingTimers() {
    let now = Date(timeIntervalSince1970: 5_000)
    var focus = BreakSnapshot(
      phase: .focusing,
      phaseDeadline: now.addingTimeInterval(-30)
    )
    BreakReducer.recover(&focus, now: now, configuration: configuration)
    XCTAssertEqual(focus.phase, .breaking)
    XCTAssertEqual(focus.phaseDeadline, now.addingTimeInterval(5))

    var expiredBreak = BreakSnapshot(
      phase: .breaking,
      phaseDeadline: now.addingTimeInterval(-30),
      breakKind: .short,
      completedFocusIntervals: 1
    )
    BreakReducer.recover(&expiredBreak, now: now, configuration: configuration)
    XCTAssertEqual(expiredBreak.phase, .focusing)
    XCTAssertEqual(expiredBreak.phaseDeadline, now.addingTimeInterval(20))
  }

  func testBreakStatePersistsAcrossRepositoryInstances() throws {
    let suiteName = "BreakReducerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let expected = BreakStateDocument(
      configuration: configuration,
      snapshot: BreakSnapshot(
        phase: .countdown,
        phaseDeadline: Date(timeIntervalSince1970: 9_000),
        breakKind: .long,
        completedFocusIntervals: 3,
        snoozeCount: 2
      )
    )

    try UserDefaultsBreakStore(defaults: defaults).save(expected)

    XCTAssertEqual(UserDefaultsBreakStore(defaults: defaults).load(), expected)
  }

  func testMigratesBreakStateFromLegacyBundleDomain() throws {
    let currentSuite = "BreakReducerTests.current.\(UUID().uuidString)"
    let legacySuite = "BreakReducerTests.legacy.\(UUID().uuidString)"
    let current = try XCTUnwrap(UserDefaults(suiteName: currentSuite))
    let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
    defer {
      current.removePersistentDomain(forName: currentSuite)
      legacy.removePersistentDomain(forName: legacySuite)
    }
    let expected = BreakStateDocument(
      configuration: configuration,
      snapshot: BreakSnapshot(
        phase: .focusing,
        phaseDeadline: Date(timeIntervalSince1970: 12_000)
      )
    )
    try UserDefaultsBreakStore(defaults: legacy).save(expected)

    let store = UserDefaultsBreakStore(defaults: current, legacyDefaults: legacy)
    XCTAssertEqual(store.load(), expected)
    XCTAssertEqual(UserDefaultsBreakStore(defaults: current).load(), expected)
  }

  func testLegacyBreakConfigurationDecodesWithSmartPauseDefaults() throws {
    let data = Data(
      """
      {
        "focusDuration": 1200,
        "shortBreakDuration": 20,
        "longBreakDuration": 300,
        "longBreakEvery": 4,
        "countdownDuration": 10,
        "snoozeDuration": 180
      }
      """.utf8
    )

    let decoded = try JSONDecoder().decode(BreakConfiguration.self, from: data)

    XCTAssertTrue(decoded.isEnabled)
    XCTAssertTrue(decoded.idleResetEnabled)
    XCTAssertEqual(decoded.idleResetDuration, 5 * 60)
    XCTAssertTrue(decoded.pauseDuringCalendarMeetings)
    XCTAssertTrue(decoded.pauseDuringCalls)
    XCTAssertTrue(decoded.pauseDuringVideoPlayback)
    XCTAssertTrue(decoded.pauseDuringGaming)
    XCTAssertTrue(decoded.pauseDuringScreenSharing)
  }

  private var typingConfiguration: BreakConfiguration {
    BreakConfiguration(
      focusDuration: 20,
      shortBreakDuration: 5,
      longBreakDuration: 12,
      longBreakEvery: 4,
      countdownDuration: 3,
      snoozeDuration: 7,
      typingDeferralLimit: 6
    )
  }

  private func countdownState(
    at start: Date,
    configuration: BreakConfiguration
  ) -> BreakSnapshot {
    var state = BreakSnapshot.stopped
    BreakReducer.reduce(&state, event: .start(start), configuration: configuration)
    BreakReducer.reduce(
      &state,
      event: .tick(start.addingTimeInterval(17), isTyping: true),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .countdown)
    return state
  }

  func testDueBreakWaitsWhileTypingUntilTheDeferralLimit() throws {
    let configuration = typingConfiguration
    let start = Date(timeIntervalSince1970: 6_000)
    var state = countdownState(at: start, configuration: configuration)

    let due = start.addingTimeInterval(20)
    let deferralEffects = BreakReducer.reduce(
      &state,
      event: .tick(due, isTyping: true),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .countdown)
    XCTAssertEqual(state.typingDeferredSince, due)
    XCTAssertEqual(state.completedFocusIntervals, 0)
    XCTAssertEqual(deferralEffects, [.persist])

    let stillTyping = BreakReducer.reduce(
      &state,
      event: .tick(due.addingTimeInterval(5), isTyping: true),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .countdown)
    XCTAssertEqual(stillTyping, [])

    let forcedEffects = BreakReducer.reduce(
      &state,
      event: .tick(due.addingTimeInterval(6), isTyping: true),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .breaking)
    XCTAssertNil(state.typingDeferredSince)
    XCTAssertEqual(state.completedFocusIntervals, 1)
    XCTAssertTrue(forcedEffects.contains(.presentBreak))
  }

  func testDeferredBreakBeginsAtTheFirstPauseInTyping() throws {
    let configuration = typingConfiguration
    let start = Date(timeIntervalSince1970: 6_500)
    var state = countdownState(at: start, configuration: configuration)

    let due = start.addingTimeInterval(20)
    BreakReducer.reduce(&state, event: .tick(due, isTyping: true), configuration: configuration)
    XCTAssertEqual(state.phase, .countdown)

    let paused = due.addingTimeInterval(2)
    let effects = BreakReducer.reduce(
      &state,
      event: .tick(paused, isTyping: false),
      configuration: configuration
    )

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertNil(state.typingDeferredSince)
    XCTAssertEqual(state.phaseDeadline, paused.addingTimeInterval(configuration.shortBreakDuration))
    XCTAssertTrue(effects.contains(.presentBreak))
  }

  func testTypingDoesNotDeferTheBreakWhenDeferralIsDisabled() throws {
    var configuration = typingConfiguration
    configuration.typingDeferralEnabled = false
    let start = Date(timeIntervalSince1970: 7_000)
    var state = countdownState(at: start, configuration: configuration)

    let due = start.addingTimeInterval(20)
    BreakReducer.reduce(&state, event: .tick(due, isTyping: true), configuration: configuration)

    XCTAssertEqual(state.phase, .breaking)
    XCTAssertNil(state.typingDeferredSince)
  }

  func testAutomaticPauseRestartsTheTypingDeferralBudget() throws {
    let configuration = typingConfiguration
    let start = Date(timeIntervalSince1970: 7_500)
    var state = countdownState(at: start, configuration: configuration)

    let due = start.addingTimeInterval(20)
    BreakReducer.reduce(&state, event: .tick(due, isTyping: true), configuration: configuration)
    XCTAssertNotNil(state.typingDeferredSince)

    BreakReducer.reduce(
      &state,
      event: .contextChanged(due.addingTimeInterval(1), reasons: [.call]),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .paused)
    XCTAssertNil(state.typingDeferredSince)

    let resumed = due.addingTimeInterval(300)
    BreakReducer.reduce(
      &state,
      event: .contextChanged(resumed, reasons: []),
      configuration: configuration
    )
    XCTAssertEqual(state.phase, .countdown)

    BreakReducer.reduce(&state, event: .tick(resumed, isTyping: true), configuration: configuration)
    XCTAssertEqual(state.phase, .countdown)
    XCTAssertEqual(state.typingDeferredSince, resumed)
  }
}
