import AppKit
import ClarityBreaks
import ClarityCore
import Observation

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
  private let store: ClarityStore
  private let statusItem: NSStatusItem
  private let menu = NSMenu()

  private var statusLineItem: NSMenuItem!
  private var enabledItem: NSMenuItem!
  private var modeItems: [NSMenuItem] = []
  private var profileItems: [NSMenuItem] = []
  private var pauseItem: NSMenuItem!
  private var resetColorsItem: NSMenuItem!
  private var breakStatusItem: NSMenuItem!
  private var startBreakItem: NSMenuItem!
  private var startFocusItem: NSMenuItem!
  private var resetFocusItem: NSMenuItem!
  private var pauseBreaksItem: NSMenuItem!
  private var pauseReasonItems: [NSMenuItem] = []
  private var snoozeItem: NSMenuItem!
  private var skipItem: NSMenuItem!
  private var stopBreakTimerItem: NSMenuItem!

  init(store: ClarityStore) {
    self.store = store
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()
    buildMenu()
    refreshStatusButton()
    observeStatusButton()
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshMenuItems()
  }

  private func buildMenu() {
    menu.autoenablesItems = false
    menu.delegate = self

    statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusLineItem.isEnabled = false
    menu.addItem(statusLineItem)

    enabledItem = actionItem("Enabled", #selector(toggleEnabled))
    menu.addItem(enabledItem)

    let modeMenu = NSMenu(title: "Mode")
    modeMenu.autoenablesItems = false
    modeItems = ControlMode.allCases.enumerated().map { index, mode in
      let item = actionItem(mode.name, #selector(selectMode(_:)))
      item.tag = index
      modeMenu.addItem(item)
      return item
    }
    let modeRoot = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
    modeRoot.submenu = modeMenu
    menu.addItem(modeRoot)

    let profileMenu = NSMenu(title: "Profile")
    profileMenu.autoenablesItems = false
    profileItems = ClarityProfile.allCases.enumerated().map { index, profile in
      let item = actionItem(profile.name, #selector(selectProfile(_:)))
      item.tag = index
      profileMenu.addItem(item)
      return item
    }
    let profileRoot = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
    profileRoot.submenu = profileMenu
    menu.addItem(profileRoot)

    menu.addItem(.separator())

    pauseItem = actionItem("Pause", #selector(togglePause))
    menu.addItem(pauseItem)
    resetColorsItem = actionItem("Reset Colors", #selector(resetColors))
    menu.addItem(resetColorsItem)

    menu.addItem(.separator())

    breakStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    breakStatusItem.isEnabled = false
    menu.addItem(breakStatusItem)

    startBreakItem = actionItem("Start Break Now", #selector(startBreakNow))
    menu.addItem(startBreakItem)
    startFocusItem = actionItem("Start Focus Timer", #selector(startFocusTimer))
    menu.addItem(startFocusItem)
    resetFocusItem = actionItem("Reset Focus Timer", #selector(startFocusTimer))
    menu.addItem(resetFocusItem)
    pauseBreaksItem = actionItem("Pause Breaks", #selector(toggleBreakPause))
    menu.addItem(pauseBreaksItem)

    pauseReasonItems = BreakPauseReason.allCases.map { reason in
      let item = NSMenuItem(title: "Paused · \(reason.name)", action: nil, keyEquivalent: "")
      item.isEnabled = false
      item.isHidden = true
      menu.addItem(item)
      return item
    }

    snoozeItem = actionItem("Snooze Break", #selector(snoozeBreak))
    menu.addItem(snoozeItem)
    skipItem = actionItem("Skip Break", #selector(skipBreak))
    menu.addItem(skipItem)
    stopBreakTimerItem = actionItem("Stop Break Timer", #selector(stopBreakTimer))
    menu.addItem(stopBreakTimerItem)

    menu.addItem(.separator())

    menu.addItem(actionItem("Open Clarity", #selector(openClarity)))
    menu.addItem(actionItem("Settings…", #selector(openSettings)))

    menu.addItem(.separator())
    menu.addItem(actionItem("Quit Clarity Completely", #selector(quitClarity)))

    statusItem.menu = menu
    refreshMenuItems()
  }

  private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func refreshStatusButton() {
    guard let button = statusItem.button else { return }
    let symbolName = store.isEnabled && !store.isPaused ? "sun.horizon.fill" : "sun.horizon"
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Clarity")
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.toolTip = "Clarity · \(store.menuBarTitle)"
    button.setAccessibilityLabel("Clarity · \(store.menuBarTitle)")
  }

  private func observeStatusButton() {
    withObservationTracking {
      _ = store.menuBarTitle
      _ = store.isEnabled
      _ = store.isPaused
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        refreshStatusButton()
        observeStatusButton()
      }
    }
  }

  private func refreshMenuItems() {
    statusLineItem.title = statusText
    enabledItem.state = store.isEnabled ? .on : .off

    for (item, mode) in zip(modeItems, ControlMode.allCases) {
      item.state = store.controlMode == mode ? .on : .off
    }
    for (item, profile) in zip(profileItems, ClarityProfile.allCases) {
      item.state = store.selectedProfile == profile ? .on : .off
    }

    pauseItem.title = store.isPaused ? "Resume" : "Pause"
    pauseItem.isEnabled = store.isEnabled
    resetColorsItem.isEnabled = store.isEnabled || store.driverMode != .idle

    let controller = store.breakController
    let phase = controller.snapshot.phase
    breakStatusItem.title = "Breaks · \(controller.phaseLabel)"
    startBreakItem.isHidden = ![.stopped, .focusing, .countdown].contains(phase)
    startFocusItem.isHidden = phase != .stopped
    resetFocusItem.isHidden = ![.focusing, .countdown, .paused].contains(phase)
    pauseBreaksItem.isHidden = phase == .stopped
    pauseBreaksItem.title = controller.isManuallyPaused ? "Resume Breaks" : "Pause Breaks"
    pauseBreaksItem.isEnabled = phase != .paused || controller.isManuallyPaused

    let activeReasons = Set(controller.activePauseReasons)
    for (item, reason) in zip(pauseReasonItems, BreakPauseReason.allCases) {
      item.isHidden = !activeReasons.contains(reason)
    }

    let canSnoozeOrSkip = [.countdown, .breaking].contains(phase)
    snoozeItem.isHidden = !canSnoozeOrSkip
    skipItem.isHidden = !canSnoozeOrSkip
    stopBreakTimerItem.isHidden = phase == .stopped
  }

  private var statusText: String {
    guard let adjustment = store.currentAdjustment else {
      return store.statusLabel
    }
    return "\(store.statusLabel) · \(adjustment.kelvin) K · \(Int(adjustment.brightness * 100))%"
  }

  @objc private func toggleEnabled() {
    store.setEnabled(!store.isEnabled)
  }

  @objc private func selectMode(_ sender: NSMenuItem) {
    guard ControlMode.allCases.indices.contains(sender.tag) else { return }
    store.setControlMode(ControlMode.allCases[sender.tag])
  }

  @objc private func selectProfile(_ sender: NSMenuItem) {
    guard ClarityProfile.allCases.indices.contains(sender.tag) else { return }
    store.activateProfile(ClarityProfile.allCases[sender.tag])
  }

  @objc private func togglePause() {
    store.togglePause()
  }

  @objc private func resetColors() {
    store.reset()
  }

  @objc private func startBreakNow() {
    store.breakController.startBreakNow()
  }

  @objc private func startFocusTimer() {
    store.breakController.startCycle()
  }

  @objc private func toggleBreakPause() {
    store.breakController.togglePause()
  }

  @objc private func snoozeBreak() {
    store.breakController.snooze()
  }

  @objc private func skipBreak() {
    store.breakController.skip()
  }

  @objc private func stopBreakTimer() {
    store.breakController.stopCycle()
  }

  @objc private func openClarity() {
    if let window = NSApp.windows.first(where: { $0.title == "Clarity" && !($0 is NSPanel) }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      performMainMenuItem(titled: "New Clarity Window")
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openSettings() {
    let didOpen = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    if !didOpen {
      performMainMenuItem(titled: "Settings…")
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitClarity() {
    NSApp.terminate(nil)
  }

  private func performMainMenuItem(titled title: String) {
    for rootItem in NSApp.mainMenu?.items ?? [] {
      guard let item = rootItem.submenu?.items.first(where: { $0.title == title }) else {
        continue
      }
      guard let action = item.action else { return }
      NSApp.sendAction(action, to: item.target, from: item)
      return
    }
  }
}
