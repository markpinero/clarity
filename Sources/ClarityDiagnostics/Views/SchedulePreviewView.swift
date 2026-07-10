import ClarityCore
import SwiftUI

struct SchedulePreviewView: View {
  let preview: SchedulePreview
  let currentMinute: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        let width = max(proxy.size.width, 0)
        let height = max(proxy.size.height, 0)

        ZStack(alignment: .leading) {
          LinearGradient(
            stops: preview.samples.map { sample in
              Gradient.Stop(
                color: color(for: sample.adjustment),
                location: Double(sample.minute) / 1_440
              )
            },
            startPoint: .leading,
            endPoint: .trailing
          )
          .clipShape(RoundedRectangle(cornerRadius: 7))

          marker(
            color: .yellow,
            x: width * preview.dayStartMinute / 1_440,
            height: height
          )
          marker(
            color: .indigo,
            x: width * preview.nightStartMinute / 1_440,
            height: height
          )
          marker(
            color: .white,
            x: width * normalizedMinute(currentMinute) / 1_440,
            height: height
          )
          .shadow(color: .black.opacity(0.6), radius: 1)
        }
      }
      .frame(height: 34)

      HStack {
        Text("12 AM")
        Spacer()
        Text("6 AM")
        Spacer()
        Text("12 PM")
        Spacer()
        Text("6 PM")
        Spacer()
        Text("12 AM")
      }
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        Label(
          TimeFormatting.label(forMinute: Int(preview.dayStartMinute.rounded())),
          systemImage: "sunrise.fill"
        )
        Label(
          TimeFormatting.label(forMinute: Int(preview.nightStartMinute.rounded())),
          systemImage: "sunset.fill"
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Schedule preview. Day begins at \(TimeFormatting.label(forMinute: Int(preview.dayStartMinute.rounded()))), night begins at \(TimeFormatting.label(forMinute: Int(preview.nightStartMinute.rounded())))."
    )
  }

  private func marker(color: Color, x: Double, height: Double) -> some View {
    Rectangle()
      .fill(color)
      .frame(width: 2, height: height)
      .position(x: x, y: height / 2)
  }

  private func color(for adjustment: DisplayAdjustment) -> Color {
    let warmth = min(max((6_500 - Double(adjustment.kelvin)) / 4_500, 0), 1)
    let brightness = Double(min(max(adjustment.brightness, 0), 1))
    return Color(
      red: brightness,
      green: brightness * (1 - 0.28 * warmth),
      blue: brightness * (1 - 0.72 * warmth)
    )
  }

  private func normalizedMinute(_ minute: Double) -> Double {
    let result = minute.truncatingRemainder(dividingBy: 1_440)
    return result >= 0 ? result : result + 1_440
  }
}
