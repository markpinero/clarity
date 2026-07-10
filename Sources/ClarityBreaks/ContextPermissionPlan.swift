import Foundation

public enum ContextPermission: String, CaseIterable, Hashable, Sendable {
  case calendar
  case accessibility
  case screenRecording
}

public enum ContextPermissionState: String, Equatable, Sendable {
  case notDetermined = "Not requested"
  case granted = "Granted"
  case denied = "Needs access"
  case restricted = "Restricted"
  case notRequired = "No prompt required"
}

public enum ContextPermissionAction: Equatable, Sendable {
  case requestSystemPermission
  case openSystemSettings
  case none
}

public enum ContextPermissionPlan {
  public static func action(for state: ContextPermissionState) -> ContextPermissionAction {
    switch state {
    case .notDetermined:
      .requestSystemPermission
    case .denied, .restricted:
      .openSystemSettings
    case .granted, .notRequired:
      .none
    }
  }
}
