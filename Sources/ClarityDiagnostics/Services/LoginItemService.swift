import ServiceManagement

@MainActor
final class LoginItemService {
  enum State: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
    case failed(String)

    var isEnabled: Bool {
      switch self {
      case .enabled, .requiresApproval:
        true
      case .disabled, .unavailable, .failed:
        false
      }
    }

    var label: String {
      switch self {
      case .disabled: "Off"
      case .enabled: "On"
      case .requiresApproval: "Approval required in System Settings"
      case .unavailable: "Unavailable from this app location"
      case .failed(let message): message
      }
    }
  }

  private(set) var state: State = .disabled

  init() {
    refresh()
  }

  func refresh() {
    switch SMAppService.mainApp.status {
    case .notRegistered:
      state = .disabled
    case .enabled:
      state = .enabled
    case .requiresApproval:
      state = .requiresApproval
    case .notFound:
      state = .unavailable
    @unknown default:
      state = .unavailable
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refresh()
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
