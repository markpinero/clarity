import ClarityBreaks
import Foundation

final class ContextPermissionRequestHistory {
  private static let storageKey = "contextPermissions.requested"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func contains(_ permission: ContextPermission) -> Bool {
    requestedPermissions.contains(permission.rawValue)
  }

  func markRequested(_ permission: ContextPermission) {
    var permissions = requestedPermissions
    permissions.insert(permission.rawValue)
    defaults.set(Array(permissions).sorted(), forKey: Self.storageKey)
  }

  private var requestedPermissions: Set<String> {
    Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
  }
}
