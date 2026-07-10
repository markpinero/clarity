import ClarityBreaks
import ClarityCore
import SwiftUI

struct SettingsView: View {
  @Bindable var store: ClarityStore
  @State private var ruleBundleIdentifier = ""
  @State private var ruleDisplayName = ""
  @State private var ruleAction = ActiveAppAction.pause

  var body: some View {
    TabView {
      scheduleSettings
        .tabItem {
          Label("Schedule", systemImage: "clock")
        }

      displaySettings
        .tabItem {
          Label("Displays", systemImage: "display.2")
        }

      generalSettings
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      breakSettings
        .tabItem {
          Label("Breaks", systemImage: "eye")
        }

      automationSettings
        .tabItem {
          Label("Automation", systemImage: "bolt.badge.clock")
        }

      safetySettings
        .tabItem {
          Label("Safety", systemImage: "shield.checkered")
        }
    }
    .frame(width: 620, height: 520)
    .scenePadding()
  }

  private var scheduleSettings: some View {
    Form {
      Section("Automatic Schedule") {
        Picker(
          "Driven by",
          selection: Binding(
            get: { store.automaticScheduleKind },
            set: { store.setAutomaticScheduleKind($0) }
          )
        ) {
          ForEach(AutomaticScheduleKind.allCases) { kind in
            Text(kind.name).tag(kind)
          }
        }
        .pickerStyle(.segmented)
      }

      if store.automaticScheduleKind == .clock {
        clockScheduleSettings
      } else {
        solarLocationSettings
        solarScheduleSettings
      }

      Section("Preview") {
        SchedulePreviewView(
          preview: store.schedulePreview,
          currentMinute: store.currentMinute
        )
        .padding(.vertical, 4)

        if store.automaticScheduleKind == .solar && store.currentSolarEvents == nil {
          Label(
            "Add a location to use sunrise and sunset. Clarity is currently falling back to the clock schedule.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var clockScheduleSettings: some View {
    Section("Day") {
      timePicker(
        "Starts",
        selection: Binding(
          get: { store.schedule.dayStartMinute },
          set: { store.updateDayStartMinute($0) }
        )
      )

      profilePicker(
        "Profile",
        selection: Binding(
          get: { store.schedule.dayProfile },
          set: { store.updateDayProfile($0) }
        )
      )
    }

    Section("Night") {
      timePicker(
        "Starts",
        selection: Binding(
          get: { store.schedule.nightStartMinute },
          set: { store.updateNightStartMinute($0) }
        )
      )

      profilePicker(
        "Profile",
        selection: Binding(
          get: { store.schedule.nightProfile },
          set: { store.updateNightProfile($0) }
        )
      )
    }

    transitionPicker(
      selection: Binding(
        get: { store.schedule.transitionMinutes },
        set: { store.updateTransitionMinutes($0) }
      )
    )
  }

  @ViewBuilder
  private var solarLocationSettings: some View {
    Section("Location") {
      Picker(
        "Source",
        selection: Binding(
          get: { store.solarLocation.source },
          set: { store.setSolarLocationSource($0) }
        )
      ) {
        ForEach(SolarLocationSource.allCases) { source in
          Text(source.name).tag(source)
        }
      }
      .pickerStyle(.segmented)

      if store.solarLocation.source == .automatic {
        LabeledContent("Status") {
          Text(store.locationState.label)
            .foregroundStyle(.secondary)
        }

        Button("Request Coarse Location") {
          store.requestOneTimeLocation()
        }
        .disabled(store.locationState == .requesting)

        Text("Clarity requests location once and stores coordinates rounded to 0.1°.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        TextField(
          "Latitude",
          value: Binding(
            get: { store.solarLocation.manualCoordinate?.latitude ?? 0 },
            set: { store.updateManualLatitude($0) }
          ),
          format: .number.precision(.fractionLength(4))
        )

        TextField(
          "Longitude",
          value: Binding(
            get: { store.solarLocation.manualCoordinate?.longitude ?? 0 },
            set: { store.updateManualLongitude($0) }
          ),
          format: .number.precision(.fractionLength(4))
        )
      }
    }
  }

  @ViewBuilder
  private var solarScheduleSettings: some View {
    Section("Solar Profiles") {
      profilePicker(
        "Day",
        selection: Binding(
          get: { store.solarSchedule.dayProfile },
          set: { store.updateSolarDayProfile($0) }
        )
      )

      profilePicker(
        "Night",
        selection: Binding(
          get: { store.solarSchedule.nightProfile },
          set: { store.updateSolarNightProfile($0) }
        )
      )

      profilePicker(
        "Sleep",
        selection: Binding(
          get: { store.solarSchedule.sleepProfile },
          set: { store.updateSolarSleepProfile($0) }
        )
      )
    }

    Section("Sleep Window") {
      Toggle(
        "Use sleep adjustment",
        isOn: Binding(
          get: { store.solarSchedule.usesSleepAdjustment },
          set: { store.setSolarSleepEnabled($0) }
        )
      )

      if store.solarSchedule.usesSleepAdjustment {
        timePicker(
          "Bedtime",
          selection: Binding(
            get: { store.solarSchedule.bedtimeMinute },
            set: { store.updateSolarBedtimeMinute($0) }
          )
        )
        timePicker(
          "Wake",
          selection: Binding(
            get: { store.solarSchedule.wakeMinute },
            set: { store.updateSolarWakeMinute($0) }
          )
        )
      }
    }

    transitionPicker(
      selection: Binding(
        get: { store.solarSchedule.transitionMinutes },
        set: { store.updateSolarTransitionMinutes($0) }
      )
    )
  }

  private var displaySettings: some View {
    Form {
      Section {
        Text(
          "Disable Clarity on a display or give it a fixed profile instead of the global policy."
        )
        .foregroundStyle(.secondary)
      }

      ForEach(store.displays) { display in
        Section {
          DisplaySettingsRow(store: store, display: display)
        }
      }

      if store.displays.isEmpty {
        ContentUnavailableView(
          "No Displays Found",
          systemImage: "display.trianglebadge.exclamationmark",
          description: Text("Refresh displays from the Clarity control window.")
        )
      }
    }
    .formStyle(.grouped)
  }

  private var generalSettings: some View {
    Form {
      Section("Startup") {
        Toggle(
          "Launch Clarity at login",
          isOn: Binding(
            get: { store.loginItemState.isEnabled },
            set: { store.setLaunchAtLogin($0) }
          )
        )

        LabeledContent("Status", value: store.loginItemState.label)

        if store.loginItemState == .requiresApproval {
          Button("Open Login Items Settings") {
            store.openLoginItemSettings()
          }
        }
      }

      Section("App Visibility") {
        Toggle(
          "Hide from Dock and ⌘-Tab",
          isOn: Binding(
            get: { store.hideFromAppSwitcher },
            set: { store.setHideFromAppSwitcher($0) }
          )
        )

        Text(
          "Clarity remains available from the menu bar. macOS controls Dock and app-switcher visibility together."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Location Privacy") {
        Text(
          "Automatic solar scheduling uses a one-time Core Location request. Clarity stores only coordinates rounded to 0.1° and does not continuously monitor location."
        )
        .foregroundStyle(.secondary)
      }

      Section("Settings File") {
        HStack {
          Button("Import…") {
            store.importSettings()
          }
          Button("Export…") {
            store.exportSettings()
          }
        }
        Text("Imported settings start Off so a file cannot immediately alter displays.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Panic Reset") {
        LabeledContent("Global shortcut", value: store.panicResetHotKeyLabel)
        Text("Restores captured display tables and turns Clarity off from any application.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var automationSettings: some View {
    Form {
      Section("Context") {
        Toggle(
          "Pause in full-screen applications",
          isOn: Binding(
            get: { store.pauseInFullscreen },
            set: { store.setPauseInFullscreen($0) }
          )
        )
        Text("Uses on-screen window bounds only; no Screen Recording permission is requested.")
          .font(.caption)
          .foregroundStyle(.secondary)

        LabeledContent("Active application", value: store.activeApplication.displayName)
        if let bundleIdentifier = store.activeApplication.bundleIdentifier {
          LabeledContent("Bundle identifier", value: bundleIdentifier)
            .font(.caption)
        }
      }

      Section("Add Application Rule") {
        TextField("Display name", text: $ruleDisplayName)
        TextField("Bundle identifier", text: $ruleBundleIdentifier)
          .textContentType(.none)

        Picker("When active", selection: $ruleAction) {
          ForEach(availableAutomationActions, id: \.self) { action in
            Text(action.name).tag(action)
          }
        }

        Button("Add Rule") {
          store.addActiveAppRule(
            bundleIdentifier: ruleBundleIdentifier,
            displayName: ruleDisplayName,
            action: ruleAction
          )
          ruleBundleIdentifier = ""
          ruleDisplayName = ""
          ruleAction = .pause
        }
        .disabled(ruleBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      Section("Application Rules") {
        if store.activeAppRules.isEmpty {
          Text("No application rules")
            .foregroundStyle(.secondary)
        }

        ForEach(store.activeAppRules) { rule in
          HStack {
            VStack(alignment: .leading) {
              Text(rule.displayName)
              Text(rule.bundleIdentifier)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
              "Action",
              selection: Binding(
                get: { rule.action },
                set: { store.updateActiveAppRule(id: rule.id, action: $0) }
              )
            ) {
              ForEach(availableAutomationActions, id: \.self) { action in
                Text(action.name).tag(action)
              }
            }
            .labelsHidden()

            Button(role: .destructive) {
              store.removeActiveAppRule(id: rule.id)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove rule for \(rule.displayName)")
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var breakSettings: some View {
    Form {
      Section("Timer") {
        Picker(
          "Focus interval",
          selection: Binding(
            get: { store.breakController.configuration.focusDuration },
            set: { duration in
              store.breakController.updateConfiguration { $0.focusDuration = duration }
            }
          )
        ) {
          ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90], id: \.self) { minutes in
            Text("\(minutes) minutes").tag(TimeInterval(minutes * 60))
          }
        }

        Picker(
          "Eye break",
          selection: Binding(
            get: { store.breakController.configuration.shortBreakDuration },
            set: { duration in
              store.breakController.updateConfiguration { $0.shortBreakDuration = duration }
            }
          )
        ) {
          ForEach([10, 20, 30, 45, 60, 120, 300, 600], id: \.self) { seconds in
            Text(Self.breakDurationLabel(seconds)).tag(TimeInterval(seconds))
          }
        }

        Picker(
          "Long break",
          selection: Binding(
            get: { store.breakController.configuration.longBreakDuration },
            set: { duration in
              store.breakController.updateConfiguration { $0.longBreakDuration = duration }
            }
          )
        ) {
          ForEach([3, 5, 10], id: \.self) { minutes in
            Text("\(minutes) minutes").tag(TimeInterval(minutes * 60))
          }
        }

        Picker(
          "Long break every",
          selection: Binding(
            get: { store.breakController.configuration.longBreakEvery },
            set: { interval in
              store.breakController.updateConfiguration { $0.longBreakEvery = interval }
            }
          )
        ) {
          ForEach([2, 4, 6], id: \.self) { interval in
            Text("\(interval) focus intervals").tag(interval)
          }
        }
      }

      Section("Focused Screen Time") {
        Toggle(
          "Reset after idle time",
          isOn: Binding(
            get: { store.breakController.configuration.idleResetEnabled },
            set: { enabled in
              store.breakController.updateConfiguration { $0.idleResetEnabled = enabled }
            }
          )
        )

        if store.breakController.configuration.idleResetEnabled {
          Picker(
            "Natural break after",
            selection: Binding(
              get: { store.breakController.configuration.idleResetDuration },
              set: { duration in
                store.breakController.updateConfiguration { $0.idleResetDuration = duration }
              }
            )
          ) {
            ForEach([1, 3, 5, 10, 15], id: \.self) { minutes in
              Text("\(minutes) minutes").tag(TimeInterval(minutes * 60))
            }
          }
        }

        LabeledContent(
          "Current idle time",
          value: Self.duration(Int(store.breakController.contextMonitor.observation.idleDuration))
        )
      }

      Section("Smart Pause") {
        smartPauseToggle(
          "Calendar meetings",
          value: \.pauseDuringCalendarMeetings
        )
        smartPauseToggle("Meetings and calls", value: \.pauseDuringCalls)
        smartPauseToggle("Video playback", value: \.pauseDuringVideoPlayback)
        smartPauseToggle("Full-screen games", value: \.pauseDuringGaming)
        smartPauseToggle("Screen recording or sharing", value: \.pauseDuringScreenSharing)
      }

      Section("Context Permissions") {
        contextPermissionRow(
          .calendar,
          state: store.breakController.contextMonitor.calendarPermission
        )
        contextPermissionRow(
          .accessibility,
          state: store.breakController.contextMonitor.accessibilityPermission
        )
        contextPermissionRow(
          .screenRecording,
          state: store.breakController.contextMonitor.screenRecordingPermission
        )
        LabeledContent("Camera and microphone", value: "Metadata only")
      }

      Section("Actions") {
        LabeledContent("Pre-break notification", value: "10 seconds before")
        LabeledContent("Emergency exit", value: "⌃⌥⌘.")

        Picker(
          "Snooze",
          selection: Binding(
            get: { store.breakController.configuration.snoozeDuration },
            set: { duration in
              store.breakController.updateConfiguration { $0.snoozeDuration = duration }
            }
          )
        ) {
          ForEach([1, 3, 5], id: \.self) { minutes in
            Text("\(minutes) minutes").tag(TimeInterval(minutes * 60))
          }
        }
      }

      Section("Current State") {
        LabeledContent("Status", value: store.breakController.phaseLabel)
        if let seconds = store.breakController.remainingSeconds {
          LabeledContent("Remaining", value: Self.duration(seconds))
        }

        if !store.breakController.activePauseReasons.isEmpty {
          LabeledContent("Paused for") {
            Text(store.breakController.activePauseReasons.map(\.name).joined(separator: ", "))
              .multilineTextAlignment(.trailing)
          }
        }

        HStack {
          if store.breakController.snapshot.phase == .stopped {
            Button("Start Break") {
              store.breakController.startBreakNow()
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button(store.breakController.isManuallyPaused ? "Resume" : "Pause") {
              store.breakController.togglePause()
            }
            Button("Stop") {
              store.breakController.stopCycle()
            }
          }

          Button("Reset Cycle") {
            store.breakController.reset()
          }
        }
      }

      Section {
        Text(
          "Break windows remain advisory. Context permissions are used only for enabled pause detectors; Clarity does not block input, kill applications, or prevent quitting."
        )
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func contextPermissionRow(
    _ permission: ContextPermission,
    state: ContextPermissionState
  ) -> some View {
    HStack {
      LabeledContent(permissionTitle(permission), value: state.rawValue)
      Spacer()
      switch ContextPermissionPlan.action(for: state) {
      case .requestSystemPermission:
        Button("Allow") {
          store.breakController.requestContextPermission(permission)
        }
      case .openSystemSettings:
        Button("Open Settings") {
          store.breakController.requestContextPermission(permission)
        }
      case .none:
        EmptyView()
      }
    }
  }

  private func permissionTitle(_ permission: ContextPermission) -> String {
    switch permission {
    case .calendar: "Calendar"
    case .accessibility: "Accessibility"
    case .screenRecording: "Screen Recording"
    }
  }

  private var availableAutomationActions: [ActiveAppAction] {
    [.pause] + ClarityProfile.allCases.map(ActiveAppAction.profile)
  }

  private func smartPauseToggle(
    _ title: String,
    value: WritableKeyPath<BreakConfiguration, Bool>
  ) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { store.breakController.configuration[keyPath: value] },
        set: { enabled in
          store.breakController.updateConfiguration { $0[keyPath: value] = enabled }
        }
      )
    )
  }

  private static func duration(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
  }

  private static func breakDurationLabel(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) seconds" }
    let minutes = seconds / 60
    return "\(minutes) minute\(minutes == 1 ? "" : "s")"
  }

  private var safetySettings: some View {
    Form {
      Section("Restoration") {
        Label(
          "Pause and Reset restore the tables captured when Clarity launched.",
          systemImage: "arrow.uturn.backward.circle")
        Label("Normal Quit also attempts restoration.", systemImage: "power")
      }

      Section("Current Hardware") {
        LabeledContent("Online displays", value: "\(store.displays.count)")
        LabeledContent("Gamma supported", value: "\(store.supportedDisplayCount)")
      }

      Section {
        Text(
          "Force quit and crash recovery are not guaranteed. Use Reset before destructive testing."
        )
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func transitionPicker(selection: Binding<Int>) -> some View {
    Section("Transitions") {
      Picker("Duration", selection: selection) {
        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
          Text("\(minutes) minutes").tag(minutes)
        }
      }
    }
  }

  private func timePicker(_ title: String, selection: Binding<Int>) -> some View {
    Picker(title, selection: selection) {
      ForEach(Array(stride(from: 0, to: 1_440, by: 15)), id: \.self) { minute in
        Text(TimeFormatting.label(forMinute: minute)).tag(minute)
      }
    }
  }

  private func profilePicker(
    _ title: String,
    selection: Binding<ClarityProfile>
  ) -> some View {
    Picker(title, selection: selection) {
      ForEach(ClarityProfile.allCases) { profile in
        Text("\(profile.name) · \(profile.adjustment.kelvin) K").tag(profile)
      }
    }
  }
}
