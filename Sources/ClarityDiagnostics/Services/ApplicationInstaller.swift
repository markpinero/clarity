import AppKit
import ClarityCore

@MainActor
enum ApplicationInstaller {
  static func promptToMoveIfNeeded(bundleURL: URL = Bundle.main.bundleURL) {
    guard bundleURL.pathExtension == "app",
      !ApplicationInstallationLocation.isInstalled(bundleURL: bundleURL)
    else { return }

    let alert = NSAlert()
    alert.messageText = "Move Clarity to Applications?"
    alert.informativeText =
      "Keeping Clarity in Applications makes it easier to launch, update, and grant permissions."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Not Now")

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    move(bundleURL: bundleURL)
  }

  private static func move(bundleURL: URL) {
    let fileManager = FileManager.default
    let destinationDirectory = preferredApplicationsDirectory(using: fileManager)
    let destination = destinationDirectory.appendingPathComponent(bundleURL.lastPathComponent)

    do {
      try fileManager.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
      )
      guard !fileManager.fileExists(atPath: destination.path) else {
        throw InstallerError.destinationExists(destination)
      }
      try fileManager.moveItem(at: bundleURL, to: destination)
      showMoveSuccess(destination: destination)
    } catch {
      showMoveFailure(error: error)
    }
  }

  private static func preferredApplicationsDirectory(using fileManager: FileManager) -> URL {
    let system = ApplicationInstallationLocation.systemApplicationsDirectory
    return fileManager.isWritableFile(atPath: system.path)
      ? system
      : ApplicationInstallationLocation.userApplicationsDirectory
  }

  private static func showMoveSuccess(destination: URL) {
    let alert = NSAlert()
    alert.messageText = "Clarity moved to Applications"
    alert.informativeText =
      "Quit and reopen Clarity from \(destination.deletingLastPathComponent().path)."
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private static func showMoveFailure(error: Error) {
    let applications = ApplicationInstallationLocation.systemApplicationsDirectory
    let alert = NSAlert()
    alert.messageText = "Clarity couldn’t be moved automatically"
    alert.informativeText =
      "\(error.localizedDescription) You can move Clarity.app to Applications manually."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Show Applications")
    alert.addButton(withTitle: "Not Now")

    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(applications)
    }
  }

  private enum InstallerError: LocalizedError {
    case destinationExists(URL)

    var errorDescription: String? {
      switch self {
      case .destinationExists(let destination):
        "An installed copy already exists at \(destination.path)."
      }
    }
  }
}
