import ClarityCore
import SwiftUI

struct DisplaySettingsRow: View {
  @ObservedObject var store: ClarityStore
  let display: DisplayDescriptor

  var body: some View {
    let settings = store.displaySettings(for: display.id.stableID)

    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Label(
          display.name,
          systemImage: display.isBuiltin ? "laptopcomputer" : "display"
        )
        .fontWeight(.medium)

        if display.isMain {
          Text("Main")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle(
          "Enabled",
          isOn: Binding(
            get: { settings.isEnabled },
            set: { store.setDisplayEnabled($0, stableID: display.id.stableID) }
          )
        )
        .toggleStyle(.switch)
        .disabled(!display.supportsGamma)
      }

      Picker(
        "Profile",
        selection: Binding<ClarityProfile?>(
          get: { settings.profileOverride },
          set: { store.setDisplayProfileOverride($0, stableID: display.id.stableID) }
        )
      ) {
        Text("Follow Global Policy").tag(ClarityProfile?.none)
        ForEach(ClarityProfile.allCases) { profile in
          Text("Override: \(profile.name)").tag(Optional(profile))
        }
      }
      .disabled(!display.supportsGamma || !settings.isEnabled)

      Text(
        display.supportsGamma
          ? "\(display.pixelWidth) × \(display.pixelHeight) · \(display.gammaTableCapacity) gamma samples"
          : "This display does not expose gamma tables."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }
}
