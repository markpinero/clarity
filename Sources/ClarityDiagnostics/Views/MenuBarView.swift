import AppKit
import ClarityBreaks
import ClarityCore
import SwiftUI

struct MenuBarView: View {
  @Bindable var store: ClarityStore
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(statusText)
      .font(.headline)

    Toggle(
      "Enabled",
      isOn: Binding(
        get: { store.isEnabled },
        set: { store.setEnabled($0) }
      )
    )

    Picker(
      "Mode",
      selection: Binding(
        get: { store.controlMode },
        set: { store.setControlMode($0) }
      )
    ) {
      ForEach(ControlMode.allCases) { mode in
        Text(mode.name).tag(mode)
      }
    }

    Menu("Profile") {
      ForEach(ClarityProfile.allCases) { profile in
        Button {
          store.activateProfile(profile)
        } label: {
          if store.selectedProfile == profile {
            Label(profile.name, systemImage: "checkmark")
          } else {
            Text(profile.name)
          }
        }
      }
    }

    Divider()

    Button(store.isPaused ? "Resume" : "Pause") {
      store.togglePause()
    }
    .disabled(!store.isEnabled)

    Button("Reset Colors") {
      store.reset()
    }
    .disabled(!store.isEnabled && store.driverMode == .idle)

    Divider()

    Text("Breaks · \(store.breakController.phaseLabel)")
    if store.breakController.snapshot.phase == .stopped {
      Button("Start Break Now") {
        store.breakController.startBreakNow()
      }
      Button("Start Focus Timer") {
        store.breakController.startCycle()
      }
    } else {
      if [.focusing, .countdown].contains(store.breakController.snapshot.phase) {
        Button("Start Break Now") {
          store.breakController.startBreakNow()
        }
      }

      if store.breakController.snapshot.phase != .breaking {
        Button("Reset Focus Timer") {
          store.breakController.startCycle()
        }
      }

      Button(store.breakController.isManuallyPaused ? "Resume Breaks" : "Pause Breaks") {
        store.breakController.togglePause()
      }
      .disabled(
        store.breakController.snapshot.phase == .paused
          && !store.breakController.isManuallyPaused
      )
      ForEach(store.breakController.activePauseReasons, id: \.self) { reason in
        Text("Paused · \(reason.name)")
      }
      if [.countdown, .breaking].contains(store.breakController.snapshot.phase) {
        Button("Snooze Break") {
          store.breakController.snooze()
        }
        Button("Skip Break") {
          store.breakController.skip()
        }
      }
      Button("Stop Break Timer") {
        store.breakController.stopCycle()
      }
    }

    Divider()

    Button("Open Clarity") {
      openWindow(id: "control")
      NSApp.activate(ignoringOtherApps: true)
    }

    SettingsLink {
      Text("Settings…")
    }

    Divider()

    Button("Quit Clarity Completely") {
      NSApplication.shared.terminate(nil)
    }
  }

  private var statusText: String {
    guard let adjustment = store.currentAdjustment else {
      return store.statusLabel
    }
    return "\(store.statusLabel) · \(adjustment.kelvin) K · \(Int(adjustment.brightness * 100))%"
  }
}
