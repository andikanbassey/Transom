import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var drawer: TransomController!
    var statusItem: NSStatusItem!
    var cancellable: AnyCancellable?
    let pauseItem = NSMenuItem(title: "Pause Clipboard Capture", action: #selector(togglePause), keyEquivalent: "")
    let headerItem = NSMenuItem()
    let activateItem = NSMenuItem(title: "", action: #selector(makeActive), keyEquivalent: "")
    let updateItem = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
    var updateCheckTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // transom:// links. Registered this early so a link that launches Transom is not lost.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        Automation.shared.handle(url: url, source: AutomationSource(pid: pid))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.standby = !InstanceGuard.resolveAtLaunch()
        drawer = TransomController()
        AppModel.shared.showDrawer = { [weak self] in self?.drawer.openIfClosed() }
        AppModel.shared.openSettings = { pane in
            AppModel.shared.hideDrawer()
            SettingsWindow.shared.show(pane: pane)
        }

        AppModel.shared.showOnboarding = { OnboardingWindow.shared.show() }
        HotKeyCenter.shared.action = { [weak self] in self?.drawer.toggle(focus: true) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.setAccessibilityLabel(Brand.name)
        statusItem.button?.appearsDisabled = AppModel.shared.standby

        let menu = NSMenu()
        menu.delegate = self
        // Always says which build this is and where its data lives; in standby it also says why nothing is captured.
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        activateItem.target = self
        menu.addItem(activateItem)
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        updateItem.isHidden = true
        menu.addItem(updateItem)
        menu.addItem(.separator())
        func add(_ title: String, _ symbol: String, _ action: Selector, key: String = "") {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
        }
        add("Show Transom", "rectangle.topthird.inset.filled", #selector(showDrawer))
        add("Open Library…", "macwindow", #selector(openLibrary))
        installMainMenu()
        pauseItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pauseItem.target = self
        menu.addItem(pauseItem)
        add("Clear Unpinned Clipboard", "trash", #selector(clearClipboard))
        menu.addItem(.separator())
        add("Settings…", "gearshape", #selector(showSettings), key: ",")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit \(Brand.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        statusItem.menu = menu

        // A new release shows up in the menu; the check runs at launch and then every few hours (at most one request a day).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.shared.checkIfDue() }
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in Updater.shared.checkIfDue() }

        if drawer.stayOpen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.drawer.toggle() } }
        if Env["THEME_TEST"] != nil {
            // Debug aid: open the window, flip Theme to Light, then Dark, then System, and report the window's appearance.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsWindow.shared.show(tab: .settings)
                var out = ""
                let steps: [(Appearance, Double)] = [(.light, 0.5), (.dark, 1.0), (.system, 1.5)]
                for (a, t) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        Settings.shared.v.appearance = a
                        out += "\(a.rawValue) -> \(SettingsWindow.shared.appearanceName)\n"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { try? out.write(toFile: "/tmp/transom-theme-test.txt", atomically: true, encoding: .utf8); exit(0) }
            }
        }
        if let spec = Env["SCROLL_TEST"] {
            // Debug aid: post synthetic downward scrolls at the given heights below the top of the main screen (for
            // example "1,12,300"), and write whether the drawer opened for each to /tmp/transom-scroll-test.txt.
            let ys = spec.split(separator: ",").compactMap { Double($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                var report = "trusted: \(Paster.trusted)  bandSetting: \(Settings.shared.v.scrollZone.rawValue)\n"
                let screen = NSScreen.screens[0]
                report += "frame.maxY=\(screen.frame.maxY) visible.maxY=\(screen.visibleFrame.maxY)\n"
                func run(_ i: Int) {
                    guard i < ys.count else { try? report.write(toFile: "/tmp/transom-scroll-test.txt", atomically: true, encoding: .utf8); exit(0) }
                    let x = screen.frame.midX
                    CGWarpMouseCursorPosition(CGPoint(x: x, y: ys[i]))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        var seen = 0.0
                        for sign in [-1, 1] {
                            for _ in 0..<8 {
                                guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(sign * 12), wheel2: 0, wheel3: 0),
                                      let ns = NSEvent(cgEvent: e) else { continue }
                                seen = ns.scrollingDeltaY
                                self.drawer.handleGlobalScroll(ns)
                            }
                        }
                        report += "(deltaY seen \(seen)) "
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            report += "y=\(ys[i]) opened=\(self.drawer.isVisible)\n"
                            if self.drawer.isVisible { self.drawer.toggle() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { run(i + 1) }
                        }
                    }
                }
                run(0)
            }
        }
        if Env["THUMB_TEST"] != nil {
            // Debug aid (scratch TRANSOM_SUPPORT_DIR with many pictures): loads every picture's card thumbnail, as scrolling the
            // whole history would, then writes the memory in use to /tmp/transom-thumb-test.txt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                let urls = AppModel.shared.clipboard.clips.compactMap(\.imageURL)
                Task {
                    var made = 0
                    for url in urls where await Thumbs.image(for: url, size: CGSize(width: 190, height: 215)) != nil { made += 1 }
                    let kb = (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8)) ?? ""
                    var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
                    try? "\(made) of \(urls.count) thumbnails, \(info.phys_footprint / 1_048_576) MB\(kb)\n".write(toFile: "/tmp/transom-thumb-test.txt", atomically: true, encoding: .utf8)
                }
            }
        }
        if Env["DROP_TEST"] != nil {
            // Debug aid (run it with TRANSOM_SUPPORT_DIR set to a scratch folder): drop a text, a link and a picture item on Notes and Quick Access.
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
                // A picture file in a temporary folder, as a screenshot tool leaves it.
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Shots", isDirectory: true)
                try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let shot = tmp.appendingPathComponent("shot 18-35-14.png")
                try? rep.representation(using: .png, properties: [:])?.write(to: shot)
                var file = Clip(kind: .file); file.paths = [shot.path]
                for c in [text, link, image, file] { AppModel.shared.notes.addClip(c); AppModel.shared.files.addClip(c) }
                print("notes: \(AppModel.shared.notes.notes.map(\.title))  files: \(AppModel.shared.files.paths.map { ($0 as NSString).lastPathComponent })")
            }
        }
        if Env["COPY_LATEST_IMAGE"] != nil {
            // Debug aid: copy the newest image item, print the formats now on the clipboard, then quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let store = AppModel.shared.clipboard
                guard let clip = store.clips.first(where: { $0.kind == .image }) else { print("no image item"); exit(1) }
                store.copy(clip)
                let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
                let size = NSPasteboard.general.data(forType: .png)?.count ?? 0
                print("types: \(types.joined(separator: ", "))  png bytes: \(size)")
                if Env["PASTE"] != nil {
                    print("accessibility: \(Paster.trusted)")
                    Paster.pasteNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
                } else { exit(0) }
            }
        }
        if let count = Int(Env["MARK_SENSITIVE"] ?? "") {
            // Debug aid: once the history has loaded, mark the newest items sensitive with different amounts of time left
            // (14 minutes, 20 seconds, 10 minutes, then 8 seconds), to see the countdown and the dissolve. Use a scratch folder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let store = AppModel.shared.clipboard
                for clip in store.clips.prefix(count) { store.markSensitive(clip) }
                let left: [TimeInterval] = [840, 20, 600, 8]
                for n in 0..<min(count, store.clips.count) where store.clips[n].sensitive {
                    store.clips[n].sensitiveSince = Date().addingTimeInterval(left[n % left.count] - ClipboardStore.sensitiveLifetime)
                }
            }
        }
        if let path = Env["SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(Env["SNAPSHOT_DELAY"] ?? "") ?? 3)) { self.drawer.snapshot(to: path); exit(0) }
        }
        if let path = Env["SNAPSHOT_VIEW"] {
            // Debug aid: render a view to a PNG. "settings" or "onboarding".
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(Env["SNAPSHOT_DELAY"] ?? "") ?? ((path.hasSuffix("desktop.png") || path.hasSuffix("palette.png")) ? 4 : 1))) {
                if Env["EDIT"] != nil { AppModel.shared.notes.showingList = false }
                if let sec = Env["SECTION"], let sc = DesktopSection(rawValue: sec) { MainNav.shared.section = sc }
                let view: NSView = path.hasSuffix("onboarding.png")
                    ? NSHostingView(rootView: OnboardingView(finish: {}))
                    : (path.hasSuffix("palette.png")
                        ? { MainNav.shared.paletteOpen = true; return NSHostingView(rootView: MainWindowView().frame(width: 1120, height: 740)) }()
                    : path.hasSuffix("sheet.png")
                        ? { MainNav.shared.tab = .settings; return NSHostingView(rootView: MainWindowView().frame(width: 1120, height: 740)) }()
                    : path.hasSuffix("desktop.png")
                        ? NSHostingView(rootView: DesktopView().frame(width: 1120, height: 740))
                    : path.hasSuffix("files-options.png")
                        ? NSHostingView(rootView: FilesOptionsPopover(store: AppModel.shared.files, close: {}).padding(20).background(Color(white: 0.2)))
                        : { MainNav.shared.tab = .settings; return NSHostingView(rootView: SettingsView()) }())
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.appearance = NSAppearance(named: Env["LIGHT"] != nil ? .aqua : .darkAqua)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            }
        }
        cancellable = Settings.shared.$v.sink { [weak self] v in
            self?.statusItem.isVisible = v.showMenuBarIcon
            HotKeyCenter.shared.register(v.hotkeyEnabled && !AppModel.shared.standby ? v.hotkey : nil)
        }
        // A waiting Transom takes over by itself once the other one quits.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            if AppModel.shared.standby, InstanceGuard.others().isEmpty { self?.becomeActive() }
        }

        // After the data folder moved from the old name: say so once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { LegacyData.showNoticeIfNeeded() }
        if !Settings.shared.v.onboarded, !drawer.stayOpen, Env["SNAPSHOT"] == nil {
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
        appMenu.addItem(withTitle: "Hide Transom", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Transom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let standby = AppModel.shared.standby
        let version = Brand.version.isEmpty ? "" : " \(Brand.version)"
        headerItem.title = standby ? "\(Brand.name)\(version) · waiting, not capturing" : "\(Brand.name)\(version)"
        headerItem.toolTip = "Data: \(supportDir.path)"
        updateItem.isHidden = Updater.shared.available == nil
        if let r = Updater.shared.available { updateItem.title = "Update to \(Brand.name) \(r.version)…" }
        activateItem.title = "Make \(Brand.name) the Active Copy"
        activateItem.isHidden = !standby
        pauseItem.isEnabled = !standby
    }

    @objc func installUpdate() { Updater.shared.install() }

    @objc func makeActive() {
        InstanceGuard.quit(InstanceGuard.others())
        becomeActive()
    }

    private func becomeActive() {
        AppModel.shared.standby = false
        statusItem.button?.appearsDisabled = false
        let v = Settings.shared.v
        HotKeyCenter.shared.register(v.hotkeyEnabled ? v.hotkey : nil)
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
