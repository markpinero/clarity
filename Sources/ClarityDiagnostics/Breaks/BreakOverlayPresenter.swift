import AppKit
import ClarityBreaks
import Combine
import SwiftUI

struct BreakOverlayPresentationTransition: Equatable {
  var shouldBeginBreakPresentation = false
  var shouldEndBreakPresentation = false
}

struct BreakOverlayPresentationState {
  enum Mode {
    case none
    case countdown
    case breakOverlay
  }

  private(set) var mode = Mode.none

  mutating func transition(to nextMode: Mode) -> BreakOverlayPresentationTransition {
    guard mode != nextMode else { return BreakOverlayPresentationTransition() }
    let transition = BreakOverlayPresentationTransition(
      shouldBeginBreakPresentation: nextMode == .breakOverlay,
      shouldEndBreakPresentation: mode == .breakOverlay
    )
    mode = nextMode
    return transition
  }
}

struct BreakOverlayPanelGeometry {
  static func contentRect(for windowFrame: CGRect, on screenFrame: CGRect) -> CGRect {
    windowFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
  }
}

@MainActor
final class BreakOverlayPresenter {
  private let model = BreakOverlayModel()
  private var presentationState = BreakOverlayPresentationState()
  private var panels: [NSPanel] = []
  private var globalEmergencyEscapeMonitor: Any?
  private var localEmergencyEscapeMonitor: Any?
  private var presentationOptionsBeforeBreak: NSApplication.PresentationOptions?
  private var activationPolicyBeforeBreak: NSApplication.ActivationPolicy?

  func presentCountdown(
    snapshot: BreakSnapshot,
    now: Date,
    countdownSeconds: Int,
    snoozeMinutes: Int,
    onSnooze: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    transition(to: .countdown)
    configure(
      snapshot: snapshot,
      now: now,
      totalSeconds: countdownSeconds,
      snoozeMinutes: snoozeMinutes,
      onSnooze: onSnooze,
      onSkip: onSkip
    )

    guard let screen = screenContainingPointer() else { return }
    let width = BreakCountdownAlertView.width
    let visibleFrame = screen.visibleFrame
    let panel = makePanel(
      frame: CGRect(
        x: visibleFrame.midX - width / 2, y: visibleFrame.maxY - 42, width: width, height: 1),
      screen: screen,
      level: .statusBar,
      material: .windowBackground,
      cornerRadius: 12,
      hasShadow: true,
      isOpaque: false,
      activates: false,
      content: BreakCountdownAlertView(model: model)
    )
    panel.setAccessibilityLabel("Clarity break countdown")
    panels = [panel]
    resizeCountdownPanelToFit()
    panel.orderFrontRegardless()
  }

  func presentBreak(
    snapshot: BreakSnapshot,
    now: Date,
    totalSeconds: Int,
    snoozeMinutes: Int,
    onSnooze: @escaping () -> Void,
    onSkip: @escaping () -> Void,
    onEmergencyEscape: @escaping () -> Void
  ) {
    transition(to: .breakOverlay)
    configure(
      snapshot: snapshot,
      now: now,
      totalSeconds: totalSeconds,
      snoozeMinutes: snoozeMinutes,
      onSnooze: onSnooze,
      onSkip: onSkip
    )

    panels = NSScreen.screens.map { screen in
      let panel = makePanel(
        frame: screen.frame,
        screen: screen,
        level: .screenSaver,
        material: .fullScreenUI,
        cornerRadius: 0,
        hasShadow: false,
        isOpaque: true,
        activates: true,
        content: FullBreakOverlayView(model: model)
      )
      panel.setAccessibilityLabel("Clarity break overlay")
      panel.orderFrontRegardless()
      return panel
    }
    panels.first(where: { $0.screen?.frame.contains(NSEvent.mouseLocation) == true })?
      .makeKeyAndOrderFront(nil)
    installEmergencyEscapeMonitors(onEmergencyEscape: onEmergencyEscape)
    NSSound(named: "Glass")?.play()
  }

  func update(snapshot: BreakSnapshot, now: Date) {
    model.kind = snapshot.breakKind ?? .short
    model.phaseDeadline = snapshot.phaseDeadline
    let remainingSeconds = Int(ceil(snapshot.remaining(at: now) ?? 0))
    if remainingSeconds != model.remainingSeconds {
      model.remainingSeconds = remainingSeconds
    }
    model.currentTime = now
    model.exerciseIndex = snapshot.completedFocusIntervals % model.exercises.count
    model.isWaitingForTypingPause = snapshot.typingDeferredSince != nil
    if presentationState.mode == .countdown {
      resizeCountdownPanelToFit()
    }
  }

  /// Keeps the alert exactly as tall as its content, anchored by its top edge, so the
  /// button row can never be clipped when the copy changes length.
  private func resizeCountdownPanelToFit() {
    guard let panel = panels.first, let contentView = panel.contentView else { return }
    let height = contentView.fittingSize.height
    guard height > 0, abs(height - panel.frame.height) > 0.5 else { return }
    let frame = CGRect(
      x: panel.frame.minX,
      y: panel.frame.maxY - height,
      width: panel.frame.width,
      height: height
    )
    panel.setFrame(frame, display: true)
  }

  func dismiss() {
    transition(to: .none)
  }

  private func transition(to mode: BreakOverlayPresentationState.Mode) {
    let transition = presentationState.transition(to: mode)
    removeEmergencyEscapeMonitors()
    if transition.shouldEndBreakPresentation {
      endBreakPresentation()
    }
    for panel in panels {
      panel.orderOut(nil)
    }
    panels.removeAll()
    if transition.shouldBeginBreakPresentation {
      beginBreakPresentation()
    }
  }

  private func configure(
    snapshot: BreakSnapshot,
    now: Date,
    totalSeconds: Int,
    snoozeMinutes: Int,
    onSnooze: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    model.totalSeconds = max(1, totalSeconds)
    model.snoozeMinutes = snoozeMinutes
    model.onSnooze = onSnooze
    model.onSkip = onSkip
    update(snapshot: snapshot, now: now)
  }

  private func beginBreakPresentation() {
    guard presentationOptionsBeforeBreak == nil else { return }
    presentationOptionsBeforeBreak = NSApp.presentationOptions
    activationPolicyBeforeBreak = NSApp.activationPolicy()
    if activationPolicyBeforeBreak != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async { [weak self] in
      guard self?.presentationOptionsBeforeBreak != nil else { return }
      NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }
  }

  private func endBreakPresentation() {
    guard let presentationOptionsBeforeBreak else { return }
    NSApp.presentationOptions = presentationOptionsBeforeBreak
    self.presentationOptionsBeforeBreak = nil
    if let activationPolicyBeforeBreak {
      NSApp.setActivationPolicy(activationPolicyBeforeBreak)
      self.activationPolicyBeforeBreak = nil
    }
  }

  private func installEmergencyEscapeMonitors(onEmergencyEscape: @escaping () -> Void) {
    removeEmergencyEscapeMonitors()

    globalEmergencyEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      guard Self.isEmergencyEscape(event) else { return }
      onEmergencyEscape()
    }
    localEmergencyEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard Self.isEmergencyEscape(event) else { return event }
      onEmergencyEscape()
      return nil
    }
  }

  private func removeEmergencyEscapeMonitors() {
    if let globalEmergencyEscapeMonitor {
      NSEvent.removeMonitor(globalEmergencyEscapeMonitor)
      self.globalEmergencyEscapeMonitor = nil
    }
    if let localEmergencyEscapeMonitor {
      NSEvent.removeMonitor(localEmergencyEscapeMonitor)
      self.localEmergencyEscapeMonitor = nil
    }
  }

  private static func isEmergencyEscape(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let expected: NSEvent.ModifierFlags = [.command, .option, .control]
    return modifiers == expected && event.charactersIgnoringModifiers == "."
  }

  private func screenContainingPointer() -> NSScreen? {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(pointer) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  private func makePanel<Content: View>(
    frame: CGRect,
    screen: NSScreen,
    level: NSWindow.Level,
    material: NSVisualEffectView.Material,
    cornerRadius: CGFloat,
    hasShadow: Bool,
    isOpaque: Bool,
    activates: Bool,
    content: Content
  ) -> NSPanel {
    let styleMask: NSWindow.StyleMask =
      activates ? [.borderless] : [.borderless, .nonactivatingPanel]
    let panel = NSPanel(
      contentRect: BreakOverlayPanelGeometry.contentRect(for: frame, on: screen.frame),
      styleMask: styleMask,
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.level = level
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    panel.backgroundColor = isOpaque ? .black : .clear
    panel.isOpaque = isOpaque
    panel.hasShadow = hasShadow
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.isExcludedFromWindowsMenu = true

    let effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
    effectView.material = material
    effectView.blendingMode = isOpaque ? .withinWindow : .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = cornerRadius
    effectView.layer?.masksToBounds = cornerRadius > 0

    let hostingView = NSHostingView(rootView: content)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    effectView.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
    ])
    panel.contentView = effectView
    return panel
  }
}

@MainActor
final class BreakOverlayModel: ObservableObject {
  @Published var kind = BreakKind.short
  @Published var phaseDeadline: Date?
  @Published var remainingSeconds = 0
  @Published var totalSeconds = 1
  @Published var snoozeMinutes = 3
  @Published var exerciseIndex = 0
  @Published var currentTime = Date()
  @Published var isWaitingForTypingPause = false
  var onSnooze: () -> Void = {}
  var onSkip: () -> Void = {}

  let exercises = [
    "Look at something at least 20 feet away.",
    "Blink slowly and let your eyes refocus.",
    "Drop your shoulders and relax your neck.",
  ]

  func progress(at date: Date) -> Double {
    BreakOverlayProgress.fraction(
      deadline: phaseDeadline,
      at: date,
      totalSeconds: totalSeconds
    )
  }
}

struct BreakOverlayProgress {
  static func fraction(deadline: Date?, at date: Date, totalSeconds: Int) -> Double {
    guard let deadline else { return 0 }
    let remaining = deadline.timeIntervalSince(date)
    return min(1, max(0, remaining / Double(max(1, totalSeconds))))
  }
}

private struct FullBreakOverlayView: View {
  @ObservedObject var model: BreakOverlayModel

  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.10, blue: 0.22),
          Color(red: 0.10, green: 0.20, blue: 0.42),
          Color.black,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      Circle()
        .fill(Color.cyan.opacity(0.12))
        .frame(width: 560, height: 560)
        .blur(radius: 110)
        .offset(x: -280, y: -220)

      Circle()
        .fill(Color.indigo.opacity(0.18))
        .frame(width: 680, height: 680)
        .blur(radius: 130)
        .offset(x: 340, y: 260)

      VStack(spacing: 0) {
        Text(model.currentTime.formatted(date: .omitted, time: .shortened))
          .font(.system(size: 17, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.72))
          .padding(.top, 44)

        Spacer()

        VStack(spacing: 22) {
          Image(systemName: model.kind == .long ? "figure.mind.and.body" : "eye")
            .font(.system(size: 42, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.9))

          VStack(spacing: 10) {
            Text(model.kind == .long ? "Step away for a while" : "A moment for your eyes")
              .font(.system(size: 42, weight: .semibold, design: .rounded))
            Text(model.exercises[model.exerciseIndex])
              .font(.title2)
              .foregroundStyle(.white.opacity(0.7))
          }

          ZStack {
            Circle()
              .stroke(.white.opacity(0.12), lineWidth: 8)
            TimelineView(.animation(paused: model.remainingSeconds <= 0)) { timeline in
              Circle()
                .trim(from: 0, to: model.progress(at: timeline.date))
                .stroke(
                  LinearGradient(
                    colors: [.white, .cyan.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                  ),
                  style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            }
            Text(Self.duration(model.remainingSeconds))
              .font(.system(size: 44, weight: .medium, design: .rounded).monospacedDigit())
              .contentTransition(.numericText(countsDown: true))
              .animation(.easeOut(duration: 0.2), value: model.remainingSeconds)
          }
          .frame(width: 170, height: 170)
          .accessibilityLabel("Break remaining \(Self.duration(model.remainingSeconds))")

          HStack(spacing: 12) {
            Button("Skip Break") { model.onSkip() }
              .buttonStyle(.bordered)
              .controlSize(.large)

            Button("Snooze \(model.snoozeMinutes) min") { model.onSnooze() }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
          }
        }

        Spacer()

        Text("Clarity will return you to focus when the timer ends.")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.5))
          .padding(.bottom, 42)
      }
      .padding(.horizontal, 48)
      .multilineTextAlignment(.center)
    }
    .foregroundStyle(.white)
  }

  private static func duration(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
  }
}
