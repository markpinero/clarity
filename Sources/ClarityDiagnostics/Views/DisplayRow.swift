import ClarityCore
import SwiftUI

struct DisplayRow: View {
  let display: DisplayDescriptor

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
        .frame(width: 22)
        .foregroundStyle(display.supportsGamma ? .primary : .secondary)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(display.name)
            .fontWeight(.medium)
          if display.isMain {
            Text("Main")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }

        Text(
          "\(display.pixelWidth) × \(display.pixelHeight) · \(display.gammaTableCapacity) samples"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      Label(
        display.supportsGamma ? "Supported" : "Unavailable",
        systemImage: display.supportsGamma ? "checkmark.circle.fill" : "xmark.circle"
      )
      .font(.caption)
      .foregroundStyle(display.supportsGamma ? .green : .secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
