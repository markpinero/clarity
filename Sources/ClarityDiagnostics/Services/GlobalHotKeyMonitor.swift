import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyMonitor {
  private var eventHandler: EventHandlerRef?
  private var hotKey: EventHotKeyRef?
  private var action: (() -> Void)?

  func start(action: @escaping () -> Void) throws {
    stop()
    self.action = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in monitor.action?() }
        return noErr
      },
      1,
      &eventType,
      pointer,
      &eventHandler
    )
    guard status == noErr else { throw GlobalHotKeyError.registrationFailed(status) }

    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    let identifier = EventHotKeyID(signature: Self.signature, id: 1)
    let hotKeyStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_R),
      modifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    guard hotKeyStatus == noErr else {
      stop()
      throw GlobalHotKeyError.registrationFailed(hotKeyStatus)
    }
  }

  func stop() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    hotKey = nil
    eventHandler = nil
    action = nil
  }

  private static let signature: OSType = 0x4952_4953  // IRIS
}

enum GlobalHotKeyError: LocalizedError {
  case registrationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .registrationFailed(let status):
      "Could not register the panic-reset hotkey (status \(status))."
    }
  }
}
