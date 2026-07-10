import XCTest

@testable import ClarityDiagnostics

final class BreakOverlayPresentationStateTests: XCTestCase {
  func testRepeatedBreakPresentationDoesNotRestartApplicationPresentation() {
    var state = BreakOverlayPresentationState()

    XCTAssertEqual(
      state.transition(to: .breakOverlay),
      BreakOverlayPresentationTransition(shouldBeginBreakPresentation: true)
    )
    XCTAssertEqual(
      state.transition(to: .breakOverlay),
      BreakOverlayPresentationTransition()
    )
  }

  func testLeavingBreakPresentationRestoresApplicationPresentationOnce() {
    var state = BreakOverlayPresentationState()
    _ = state.transition(to: .breakOverlay)

    XCTAssertEqual(
      state.transition(to: .none),
      BreakOverlayPresentationTransition(shouldEndBreakPresentation: true)
    )
    XCTAssertEqual(state.transition(to: .none), BreakOverlayPresentationTransition())
  }
}
