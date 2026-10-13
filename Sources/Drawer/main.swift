import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var drawer: DrawerController!
    var statusItem: NSStatusItem!
    var cancellable: AnyCancellable?
    let pauseItem = NSMenuItem(title: "Pause Clipboard Capture", action: #selector(togglePause), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        drawer = DrawerController()
        AppModel.shared.openSettings = { pane in
            AppModel.shared.hideDrawer()
            SettingsWindow.shared.show(pane: pane)
        }

        AppModel.shared.showOnboarding = { OnboardingWindow.shared.show() }
        HotKeyCenter.shared.action = { [weak self] in self?.drawer.toggle(focus: true) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.setAccessibilityLabel("Drawer")

        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ symbol: String, _ action: Selector, key: String = "") {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
        }
        add("Show Drawer", "rectangle.topthird.inset.filled", #selector(showDrawer))
        pauseItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pauseItem.target = self
        menu.addItem(pauseItem)
        add("Clear Unpinned Clipboard", "trash", #selector(clearClipboard))
        menu.addItem(.separator())
        add("Settings…", "gearshape", #selector(showSettings), key: ",")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Drawer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        statusItem.menu = menu

        if drawer.stayOpen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.drawer.toggle() } }
        if let path = ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.drawer.snapshot(to: path); exit(0) }
        }
        if let path = ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT_VIEW"] {
            // Debug aid: render a view to a PNG. "settings" or "onboarding".
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let view: NSView = path.hasSuffix("onboarding.png")
                    ? NSHostingView(rootView: OnboardingView(finish: {}))
                    : NSHostingView(rootView: SettingsView())
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.appearance = NSAppearance(named: .darkAqua)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            }
        }
        cancellable = Settings.shared.$v.sink { [weak self] v in
            self?.statusItem.isVisible = v.showMenuBarIcon
            HotKeyCenter.shared.register(v.hotkeyEnabled ? v.hotkey : nil)
        }

        if !Settings.shared.v.onboarded, !drawer.stayOpen, ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { OnboardingWindow.shared.show() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.state = Settings.shared.v.paused ? .on : .off
    }

    // Opening the app again from Finder/Applications brings up settings, the way back if the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showDrawer() {
        // Let the menu finish closing first, otherwise the global click monitor hides the drawer at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.drawer.toggle() }
    }
    @objc func togglePause() { Settings.shared.v.paused.toggle() }
    @objc func clearClipboard() { AppModel.shared.clipboard.clearUnpinned() }
    @objc func showSettings() { SettingsWindow.shared.show() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
