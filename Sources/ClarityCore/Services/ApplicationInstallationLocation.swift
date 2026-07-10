import Foundation

public enum ApplicationInstallationLocation {
  public static func isInstalled(bundleURL: URL) -> Bool {
    let bundlePath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
    return applicationsDirectories.contains { directory in
      let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
      return bundlePath == directoryPath || bundlePath.hasPrefix(directoryPath + "/")
    }
  }

  public static var systemApplicationsDirectory: URL {
    URL(fileURLWithPath: "/Applications", isDirectory: true)
  }

  public static var userApplicationsDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)
  }

  private static var applicationsDirectories: [URL] {
    [systemApplicationsDirectory, userApplicationsDirectory]
  }
}
