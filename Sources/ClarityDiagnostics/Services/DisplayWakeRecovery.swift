import Foundation

@MainActor
final class DisplayWakeRecovery {
  typealias Cancellation = @MainActor () -> Void
  typealias Schedule =
    @MainActor (
      _ delay: TimeInterval,
      _ action: @escaping @MainActor () -> Void
    ) -> Cancellation

  static let standardRetryDelays: [TimeInterval] = [0, 1, 5]

  private let retryDelays: [TimeInterval]
  private let schedule: Schedule
  private let recover: @MainActor () -> Void
  private var cancellations: [Cancellation] = []

  init(
    retryDelays: [TimeInterval] = standardRetryDelays,
    recover: @escaping @MainActor () -> Void
  ) {
    self.retryDelays = retryDelays
    self.schedule = Self.scheduleAfter
    self.recover = recover
  }

  init(
    retryDelays: [TimeInterval],
    schedule: @escaping Schedule,
    recover: @escaping @MainActor () -> Void
  ) {
    self.retryDelays = retryDelays
    self.schedule = schedule
    self.recover = recover
  }

  func start() {
    cancel()

    for delay in retryDelays {
      guard delay > 0 else {
        recover()
        continue
      }

      cancellations.append(
        schedule(delay) { [weak self] in
          self?.recover()
        }
      )
    }
  }

  func cancel() {
    cancellations.forEach { $0() }
    cancellations.removeAll()
  }

  private static func scheduleAfter(
    _ delay: TimeInterval,
    _ action: @escaping @MainActor () -> Void
  ) -> Cancellation {
    let task = Task { @MainActor in
      try await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      action()
    }
    return { task.cancel() }
  }
}
