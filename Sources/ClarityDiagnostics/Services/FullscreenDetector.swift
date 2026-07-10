import AppKit
import CoreGraphics

enum FullscreenDetector {
  static func isFullscreen(processIdentifier: pid_t?) -> Bool {
    guard let processIdentifier else { return false }
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return false
    }

    let screenSizes = NSScreen.screens.map { screen in
      CGSize(width: screen.frame.width, height: screen.frame.height)
    }

    return windows.contains { window in
      guard (window[kCGWindowOwnerPID as String] as? Int32) == processIdentifier else {
        return false
      }
      guard (window[kCGWindowLayer as String] as? Int) == 0 else { return false }
      guard let rawBounds = window[kCGWindowBounds as String] else {
        return false
      }
      guard let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary) else {
        return false
      }

      return screenSizes.contains { screenSize in
        bounds.width >= screenSize.width * 0.98
          && bounds.height >= screenSize.height * 0.98
      }
    }
  }
}
