import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var drawer: DrawerController!
    var statusItem: NSStatusItem!
    var cancellable: AnyCancellable?
    let pauseItem = NSMenuItem(title: "Pause Clipboard Capture", action: #selector(togglePause), keyEquivalent: "")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // drawer:// links. Registered this early so a link that launches Drawer is not lost.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        Automation.shared.handle(url: url, source: AutomationSource(pid: pid))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        drawer = DrawerController()
        AppModel.shared.showDrawer = { [weak self] in self?.drawer.openIfClosed() }
        AppModel.shared.openSettings = { pane in
            AppModel.shared.hideDrawer()
            SettingsWindow.shared.show(pane: pane)
        }

        AppModel.shared.showOnboarding = { OnboardingWindow.shared.show() }
        HotKeyCenter.shared.action = { [weak self] in self?.drawer.toggle(focus: true) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.setAccessibilityLabel(isBeta ? "Drawer Beta" : "Drawer")
        if isBeta { statusItem.button?.title = " β"; statusItem.button?.imagePosition = .imageLeft }

        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ symbol: String, _ action: Selector, key: String = "") {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
        }
        add("Show Drawer", "rectangle.topthird.inset.filled", #selector(showDrawer))
        add("Open Library…", "macwindow", #selector(openLibrary))
        installMainMenu()
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
        if ProcessInfo.processInfo.environment["DRAWER_DROP_TEST"] != nil {
            // Debug aid (use with the Beta build): drop a text, a link and a picture item on Notes and Quick Access.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ClipboardFolder.prepare()
                let png = NSImage(size: NSSize(width: 600, height: 380), flipped: false) { r in
                    NSGradient(colors: [.systemPink, .systemOrange, .systemYellow])?.draw(in: r, angle: 35); return true
                }
                let rep = NSBitmapImageRep(data: png.tiffRepresentation!)!
                let name = "droptest.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: ClipboardFolder.images.appendingPathComponent(name))
                var text = Clip(kind: .text); text.text = "Meeting notes\nSend the invoice on Friday"
                var link = Clip(kind: .text); link.text = "https://example.com/pricing"; link.linkTitle = "Example pricing"
                var image = Clip(kind: .image); image.imageFile = name
                for c in [text, link, image] { AppModel.shared.notes.addClip(c); AppModel.shared.files.addClip(c) }
                print("notes: \(AppModel.shared.notes.notes.map(\.title))  files: \(AppModel.shared.files.paths.map { ($0 as NSString).lastPathComponent })")
            }
        }
        if ProcessInfo.processInfo.environment["DRAWER_COPY_LATEST_IMAGE"] != nil {
            // Debug aid: copy the newest image item, print the formats now on the clipboard, then quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let store = AppModel.shared.clipboard
                guard let clip = store.clips.first(where: { $0.kind == .image }) else { print("no image item"); exit(1) }
                store.copy(clip)
                let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
                let size = NSPasteboard.general.data(forType: .png)?.count ?? 0
                print("types: \(types.joined(separator: ", "))  png bytes: \(size)")
                if ProcessInfo.processInfo.environment["DRAWER_PASTE"] != nil {
                    print("accessibility: \(Paster.trusted)")
                    Paster.pasteNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
                } else { exit(0) }
            }
        }
        if let path = ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.drawer.snapshot(to: path); exit(0) }
        }
        if let path = ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT_VIEW"] {
            // Debug aid: render a view to a PNG. "settings" or "onboarding".
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["DRAWER_SNAPSHOT_DELAY"] ?? "") ?? ((path.hasSuffix("desktop.png") || path.hasSuffix("palette.png")) ? 4 : 1))) {
                if ProcessInfo.processInfo.environment["DRAWER_EDIT"] != nil { AppModel.shared.notes.showingList = false }
                if let sec = ProcessInfo.processInfo.environment["DRAWER_SECTION"], let sc = DesktopSection(rawValue: sec) { MainNav.shared.section = sc }
                let view: NSView = path.hasSuffix("onboarding.png")
                    ? NSHostingView(rootView: OnboardingView(finish: {}))
                    : (path.hasSuffix("palette.png")
                        ? { MainNav.shared.paletteOpen = true; return NSHostingView(rootView: MainWindowView().frame(width: 1120, height: 740)) }()
                    : path.hasSuffix("desktop.png")
                        ? NSHostingView(rootView: DesktopView().frame(width: 1120, height: 740))
                    : path.hasSuffix("files-options.png")
                        ? NSHostingView(rootView: FilesOptionsPopover(store: AppModel.shared.files, close: {}).padding(20).background(Color(white: 0.2)))
                        : NSHostingView(rootView: SettingsView()))
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["DRAWER_LIGHT"] != nil ? .aqua : .darkAqua)
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

    /// A real main menu: needed once the app is in the Dock, and it gives text fields their copy and paste shortcuts.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Drawer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Drawer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let goItem = NSMenuItem(title: "Go", action: nil, keyEquivalent: ""); main.addItem(goItem)
        let go = NSMenu(title: "Go"); goItem.submenu = go
        go.addItem(withTitle: "Search…", action: #selector(openSearch), keyEquivalent: "k").target = self
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); main.addItem(windowItem)
        let window = NSMenu(title: "Window"); windowItem.submenu = window
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.state = Settings.shared.v.paused ? .on : .off
    }

    // Opening the app again from Finder/Applications brings up settings, the way back if the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show(tab: MainNav.shared.tab)
        return true
    }

    @objc func showDrawer() {
        // Let the menu finish closing first, otherwise the global click monitor hides the drawer at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.drawer.toggle() }
    }
    @objc func togglePause() { Settings.shared.v.paused.toggle() }
    @objc func clearClipboard() { AppModel.shared.clipboard.clearUnpinned() }
    @objc func showSettings() { SettingsWindow.shared.show() }
    @objc func openSearch() {
        SettingsWindow.shared.show(tab: MainNav.shared.tab)
        MainNav.shared.paletteOpen.toggle()
    }
    @objc func openLibrary() { SettingsWindow.shared.show(tab: .library) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
