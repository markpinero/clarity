import ClarityBreaks
import ClarityCore
import SwiftUI

struct OverviewView: View {
  @ObservedObject var store: ClarityStore
  @ObservedObject private var breakController: BreakController
  let onOpenSchedule: () -> Void
  @State private var showsDiagnostics = false

  init(store: ClarityStore, onOpenSchedule: @escaping () -> Void) {
    self.store = store
    _breakController = ObservedObject(wrappedValue: store.breakController)
    self.onOpenSchedule = onOpenSchedule
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        statusCard
        modePicker
        profileGrid

        if store.controlMode == .automatic {
          scheduleSummary
        }

        breakCard

        actionBar

        if let error = store.lastError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }

        diagnostics
      }
      .padding(24)
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "sun.horizon.fill")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("Clarity")
          .font(.title2.weight(.semibold))
        Text("Native display temperature and brightness")
          .foregroundStyle(.secondary)
      }

      Spacer()
      StatusBadge(store: store)
    }
  }

  private var statusCard: some View {
    GroupBox {
      HStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.isPaused ? "Display adjustments paused" : store.statusLabel)
            .font(.headline)

          if let adjustment = store.currentAdjustment {
            Text("\(adjustment.kelvin) K  •  \(Int(adjustment.brightness * 100))% brightness")
              .font(.title3.monospacedDigit())
          } else {
            Text("Captured display tables are restored")
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Toggle(
          "Enabled",
          isOn: Binding(
            get: { store.isEnabled },
            set: { store.setEnabled($0) }
          )
        )
        .toggleStyle(.switch)
        .accessibilityLabel("Clarity display adjustment enabled")
      }
      .padding(.vertical, 8)
    }
  }

  private var modePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Mode")
        .font(.headline)

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
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  private var profileGrid: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Profiles")
        .font(.headline)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
        ForEach(ClarityProfile.allCases) { profile in
          ProfileButton(
            profile: profile,
            isSelected: store.selectedProfile == profile,
            isActive: store.selectedProfile == profile
              && store.controlMode == .manual
              && store.isEnabled
              && !store.isPaused
          ) {
            store.activateProfile(profile)
          }
        }
      }
    }
  }

  private var scheduleSummary: some View {
    GroupBox("Automatic Schedule") {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label(store.automaticScheduleKind.name, systemImage: "calendar.day.timeline.left")
            .fontWeight(.medium)

          Spacer()

          Button(action: onOpenSchedule) {
            Label("Edit Schedule", systemImage: "gearshape")
          }
        }

        SchedulePreviewView(
          preview: store.schedulePreview,
          currentMinute: store.currentMinute
        )

        if store.automaticScheduleKind == .solar && store.currentSolarEvents == nil {
          Label(
            "Solar location unavailable; using clock schedule.",
            systemImage: "location.slash"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
      .padding(.vertical, 6)
    }
  }

  private var actionBar: some View {
    HStack {
      Button(store.isPaused ? "Resume" : "Pause") {
        store.togglePause()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!store.isEnabled)

      Button("Reset") {
        store.reset()
      }
      .disabled(!store.isEnabled && store.driverMode == .idle)

      Spacer()

      Button("Refresh Displays") {
        store.refreshDisplays(reason: "Manual refresh", forceApply: true)
      }
    }
  }

  private var breakCard: some View {
    GroupBox("Breaks") {
      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.breakController.phaseLabel)
            .font(.headline)
          if let remaining = store.breakController.remainingSeconds {
            Text(Self.duration(remaining))
              .font(.title3.monospacedDigit())
              .foregroundStyle(.secondary)
          } else {
            Text("20-minute focus intervals with short eye breaks")
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Toggle(
          "Enabled",
          isOn: Binding(
            get: { store.breakController.isEnabled },
            set: { store.breakController.setEnabled($0) }
          )
        )
        .toggleStyle(.switch)

        if store.breakController.isEnabled {
          switch store.breakController.snapshot.phase {
          case .stopped:
            Button("Start Break Timer") {
              store.breakController.startCycle()
            }
            .buttonStyle(.borderedProminent)
          case .paused:
            if store.breakController.isManuallyPaused {
              Button("Resume") {
                store.breakController.togglePause()
              }
            } else if let reason = store.breakController.activePauseReasons.first {
              Text(reason.name)
                .foregroundStyle(.secondary)
            }
            Button("Stop") {
              store.breakController.stopCycle()
            }
          case .countdown, .breaking:
            Button("Snooze") {
              store.breakController.snooze()
            }
            Button("Skip") {
              store.breakController.skip()
            }
            Button("Pause") {
              store.breakController.togglePause()
            }
          case .focusing:
            Button("Pause") {
              store.breakController.togglePause()
            }
            Button("Stop") {
              store.breakController.stopCycle()
            }
          }
        }
      }
      .padding(.vertical, 6)
    }
  }

  private static func duration(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
  }

  private var diagnostics: some View {
    DisclosureGroup("Displays & Activity", isExpanded: $showsDiagnostics) {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(store.displays) { display in
          DisplayRow(display: display)
        }

        Divider()

        ForEach(store.events.prefix(8)) { event in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.timestamp, format: .dateTime.hour().minute().second())
              .foregroundStyle(.secondary)
            Text(event.message)
              .foregroundStyle(event.level == .error ? .red : .primary)
          }
          .font(.caption.monospaced())
          .textSelection(.enabled)
        }
      }
      .padding(.top, 10)
    }
  }
}

private struct StatusBadge: View {
  let store: ClarityStore

  var body: some View {
    Text(store.statusLabel)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(color.opacity(0.12), in: Capsule())
      .accessibilityLabel("Clarity status: \(store.statusLabel)")
  }

  private var color: Color {
    if store.isPaused { return .orange }
    return store.isEnabled ? .green : .secondary
  }
}

private struct ProfileButton: View {
  let profile: ClarityProfile
  let isSelected: Bool
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(profile.name)
            .fontWeight(.medium)
          Text("\(profile.adjustment.kelvin) K · \(Int(profile.adjustment.brightness * 100))%")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isActive {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.quaternary.opacity(isSelected ? 0.9 : 0.35), in: RoundedRectangle(cornerRadius: 9))
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .stroke(isSelected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
    }
    .accessibilityLabel("\(profile.name), \(profile.adjustment.kelvin) kelvin")
  }

  private var symbol: String {
    switch profile {
    case .health: "sun.max"
    case .reading: "book"
    case .evening: "sunset"
    case .sleep: "moon.zzz"
    }
  }
}
