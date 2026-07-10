import Foundation

enum TimeFormatting {
  static func label(forMinute minute: Int) -> String {
    let normalized = ((minute % 1_440) + 1_440) % 1_440
    var components = DateComponents()
    components.calendar = .current
    components.hour = normalized / 60
    components.minute = normalized % 60

    guard let date = components.date else {
      return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    return date.formatted(date: .omitted, time: .shortened)
  }
}
