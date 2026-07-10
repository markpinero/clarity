import AppKit
import ClarityCore
import SwiftUI

@main
struct ClarityApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store = ClarityStore.shared

  var body: some Scene {
    WindowGroup("Clarity", id: "control") {
      ContentView(store: store)
    }
    .defaultSize(width: 760, height: 620)
    .commands {
      CommandGroup(replacing: .appTermination) {
        Button("Keep Clarity in Menu Bar") {
          store.moveToMenuBarOnly()
        }
        .keyboardShortcut("h")

        Divider()

        Button("Quit Clarity") {
          NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
      }

      CommandMenu("Clarity") {
        Button(store.isPaused ? "Resume Adjustments" : "Pause Adjustments") {
          store.togglePause()
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(!store.isEnabled)

        Button("Reset Colors") {
          store.reset()
        }
        .keyboardShortcut("0", modifiers: [.command, .option])

        Divider()

        Button("Refresh Displays") {
          store.refreshDisplays(reason: "Manual refresh", forceApply: true)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
      }
    }

    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      Label(
        store.menuBarTitle,
        systemImage: store.isEnabled && !store.isPaused ? "sun.horizon.fill" : "sun.horizon"
      )
    }

    Settings {
      SettingsView(store: store)
    }
  }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var instanceLock: SingleInstanceLock?
  private var isPrimaryInstance = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.markpinero.Clarity"
    do {
      instanceLock = try SingleInstanceLock.acquire(bundleIdentifier: bundleIdentifier)
      isPrimaryInstance = instanceLock != nil
    } catch {
      isPrimaryInstance = false
    }

    guard !isPrimaryInstance else { return }
    NSWorkspace.shared.runningApplications.first {
      $0.bundleIdentifier == bundleIdentifier
        && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }?.activate(options: [])
    NSApp.terminate(nil)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard isPrimaryInstance else { return }
    ClarityStore.shared.applyAppVisibility()
    ApplicationInstaller.promptToMoveIfNeeded()
    ClarityStore.shared.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    guard isPrimaryInstance else { return }
    ClarityStore.shared.restoreForTermination()
    instanceLock?.release()
  }
}
