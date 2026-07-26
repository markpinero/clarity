import AppKit
import ClarityBreaks
import SwiftUI

/// Pre-break notice laid out like a standard macOS alert: app icon, bold message text,
/// informative text, and a trailing button row. Sizes itself vertically so the buttons
/// are never clipped by the hosting panel.
struct BreakCountdownAlertView: View {
  @ObservedObject var model: BreakOverlayModel

  static let width: CGFloat = 320

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)

      Text(messageText)
        .font(.system(size: 13, weight: .bold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)

      Text(informativeText)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)

      HStack(spacing: 10) {
        Spacer(minLength: 0)
        Button("Skip") { model.onSkip() }
        Button("Snooze \(model.snoozeMinutes) min") { model.onSnooze() }
          .buttonStyle(.borderedProminent)
      }
      .padding(.top, 18)
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .frame(width: Self.width)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(messageText)
  }

  private var breakName: String {
    model.kind == .long ? "long break" : "eye break"
  }

  private var messageText: String {
    if model.isWaitingForTypingPause {
      return "Your \(breakName) is waiting"
    }
    return model.kind == .long ? "Long break begins soon" : "Eye break begins soon"
  }

  private var informativeText: String {
    if model.isWaitingForTypingPause {
      return "You are still typing. Clarity starts the break at your next pause."
    }
    return "Starting in \(Self.duration(model.remainingSeconds)). "
      + "Finish your thought, then look away from the screen."
  }

  private static func duration(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
  }
}
