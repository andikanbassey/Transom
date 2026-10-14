import AppKit
import SwiftUI
import Combine

final class DrawerPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// Owns the panel and decides when it opens and closes.
final class DrawerController {
    private let panel: DrawerPanel
    private(set) var isVisible = false
    private var scrollAccum: CGFloat = 0
    private var lastScroll = Date.distantPast
    private var lastHide = Date.distantPast
    private var outsideSince: Date?
    private var edgeSince: Date?
    private var needsLeave = false      // after closing, the pointer must leave the top edge before it can reopen
    private var cancellables = Set<AnyCancellable>()
    private var settings: SettingsValues { Settings.shared.v }
    /// Debug aid: `Drawer --show` opens the drawer at launch and keeps it open.
    let stayOpen = CommandLine.arguments.contains("--show")

    init() {
        panel = DrawerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: DrawerView())
        panel.onCancel = { [weak self] in self?.hide() }
        AppModel.shared.hideDrawer = { [weak self] in self?.hide() }
        AppModel.shared.hideDrawerThen = { [weak self] done in self?.hide(then: done) }

        Settings.shared.$v.sink { [weak self] v in
            self?.panel.appearance = v.appearance.nsAppearance
            self?.panel.sharingType = v.showDuringScreenSharing ? .readOnly : .none
            self?.applyHeight(v.activeHeight)
        }.store(in: &cancellables)

        // Global mouse monitors need no Accessibility permission.
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] in self?.handleGlobalScroll($0) }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleLocalScroll(event)
            return self?.horizontalForWheel(event) ?? event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleKey(event) ?? event }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.isVisible == true { self?.hide(restoreFocus: false) }
        }
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    // MARK: Scroll

    /// +1 when the fingers (or wheel) move down, -1 when they move up, whatever the natural-scrolling setting.
    private func swipeDirection(_ event: NSEvent) -> CGFloat {
        var d = event.scrollingDeltaY
        if !event.isDirectionInvertedFromDevice { d = -d }
        // Trackpads and Magic Mice report a gesture phase; wheel mice do not.
        let isTrackpad = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if isTrackpad ? settings.invertTrackpadScroll : settings.invertMouseScroll { d = -d }
        return d
    }

    /// Debug aid: if the file `debug-scroll` exists in the support folder, every scroll event is logged to it.
    private func logScroll(_ source: String, _ event: NSEvent) {
        let flag = supportDir.appendingPathComponent("debug-scroll")
        guard FileManager.default.fileExists(atPath: flag.path) else { return }
        let line = "\(source) visible=\(isVisible) dy=\(event.scrollingDeltaY) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue) " +
            "natural=\(event.isDirectionInvertedFromDevice) inWindow=\(event.window === panel) y=\(event.locationInWindow.y) h=\(panel.frame.height)\n"
        let log = supportDir.appendingPathComponent("scroll.log")
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: log, atomically: true, encoding: .utf8) }
    }

    /// Accumulate swipes in one direction; returns true once the threshold is crossed.
    private func accumulate(_ amount: CGFloat) -> Bool {
        if Date().timeIntervalSince(lastScroll) > 0.3 { scrollAccum = 0 }
        lastScroll = Date()
        scrollAccum += amount
        return scrollAccum > 12
    }

    /// How far below the top of the screen a downward scroll still opens the drawer: the menu bar's full height when it
    /// is showing (so anywhere along it works), otherwise just the edge, which is where a hidden menu bar appears.
    private func scrollBand(_ screen: NSScreen) -> CGFloat {
        let edge: CGFloat = 2
        guard settings.scrollZone == .menuBar else { return edge }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return bar > 4 ? bar : edge
    }

    func handleGlobalScroll(_ event: NSEvent) {
        if AppModel.shared.standby { return }
        logScroll("global", event)
        // While the drawer is still sliding down the pointer is over the menu bar, not the drawer: a quick swipe up
        // there arrives here, and has to close it too.
        if isVisible {
            guard event.momentumPhase.isEmpty, let screen = screenUnderMouse(),
                  NSEvent.mouseLocation.y >= screen.frame.maxY - (AppModel.shared.layout.topInset + 40) else { return }
            if accumulate(max(0, -swipeDirection(event))) { hide() }
            return
        }
        // Momentum events trail a finished swipe; ignoring them stops the drawer reopening right after it closes.
        guard settings.scrollOpen, !isVisible, event.momentumPhase.isEmpty, Date().timeIntervalSince(lastHide) > 0.8,
              let screen = screenUnderMouse() else { return }
        guard NSEvent.mouseLocation.y >= screen.frame.maxY - scrollBand(screen) else { scrollAccum = 0; return }
        if accumulate(max(0, swipeDirection(event))) { show(on: screen) }
    }

    /// Scroll events over the drawer itself: a swipe up closes it, but only in the band from the top of the screen
    /// down to the column titles. Anywhere lower the lists scroll as normal.
    private func handleLocalScroll(_ event: NSEvent) {
        logScroll("local", event)
        guard isVisible, event.window === panel, event.momentumPhase.isEmpty else { return }
        let band = AppModel.shared.layout.topInset + 40
        guard event.locationInWindow.y >= panel.frame.height - band else { lastScroll = Date(); scrollAccum = 0; return }
        if accumulate(max(0, -swipeDirection(event))) { hide() }
    }

    /// A plain wheel mouse only scrolls vertically; over a strip that scrolls sideways, turn it into sideways scrolling.
    private func horizontalForWheel(_ event: NSEvent) -> NSEvent {
        guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let root = event.window?.contentView?.superview,
              overSidewaysScroller(root.hitTest(event.locationInWindow)),
              let cg = event.cgEvent?.copy() else { return event }
        let fixed = cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let point = cg.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let delta = cg.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        cg.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point)
        cg.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: delta)
        return NSEvent(cgEvent: cg) ?? event
    }

    /// True when the view is inside a scroll view that only scrolls sideways.
    private func overSidewaysScroller(_ view: NSView?) -> Bool {
        var v = view
        while let current = v {
            if let sv = current as? NSScrollView, let doc = sv.documentView {
                return doc.frame.width > sv.contentView.bounds.width + 1 && doc.frame.height <= sv.contentView.bounds.height + 1
            }
            v = current.superview
        }
        return false
    }

    // MARK: Keys

    /// Quick paste: modifier + 1…9 pastes the nth item in the list.
    /// Keyboard use of the drawer: arrows move through clipboard items, Return pastes (⌥Return pastes plain text),
    /// Space previews, Esc steps back, ⌘F searches, and just typing starts a search. Returns true if the key was used.
    private func navigate(_ event: NSEvent) -> Bool {
        guard !(panel.firstResponder is NSTextView) || event.keyCode == 53 else { return false }
        let store = AppModel.shared.clipboard
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cards = settings.clipboardCards
        switch event.keyCode {
        case 123 where cards && flags.isEmpty: store.moveCursor(-1)
        case 124 where cards && flags.isEmpty: store.moveCursor(1)
        case 126 where !cards && flags.isEmpty: store.moveCursor(-1)
        case 125 where !cards && flags.isEmpty: store.moveCursor(1)
        case 36, 76:
            guard let clip = store.cursorClip else { return false }
            AppModel.shared.use(clip, paste: flags.contains(.option) ? true : nil, plain: flags.contains(.option))
        case 49 where flags.isEmpty:
            guard let clip = store.cursorClip else { return false }
            store.expanded = store.expanded == nil ? clip : nil
        case 53 where store.expanded != nil: store.expanded = nil
        case 3 where flags == .command: store.searching = true
        default:
            // A plain letter or number starts a search, as in Spotlight.
            guard flags.isEmpty || flags == .shift, store.expanded == nil, let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return false }
            store.searching = true
            store.query += chars
            store.cursor = nil
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isVisible, panel.isKeyWindow else { return event }
        if navigate(event) { return nil }
        guard settings.quickPaste else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == settings.quickPasteModifier.flag, let ch = event.charactersIgnoringModifiers,
              let n = Int(ch), (1...9).contains(n) else { return event }
        let list = AppModel.shared.clipboard.visible
        if n <= list.count { AppModel.shared.use(list[n - 1]) }
        return nil
    }

    // MARK: Show and hide

    /// Live height changes (dragging the bottom edge, or the settings slider) keep the top edge pinned.
    private func applyHeight(_ height: Double) {
        guard isVisible else { return }
        let h = height + max(0, AppModel.shared.layout.topInset - 14)
        var f = panel.frame
        guard abs(f.height - h) > 0.5 else { return }
        f.origin.y = f.maxY - h
        f.size.height = h
        panel.setFrame(f, display: true)
    }

    /// Show the drawer on the screen the pointer is on, if it is not already open.
    func openIfClosed() {
        guard !isVisible else { return }
        show(on: screenUnderMouse() ?? NSScreen.main!, focus: true)
    }

    func toggle(focus: Bool = false) {
        isVisible ? hide() : show(on: screenUnderMouse() ?? NSScreen.main!, focus: focus)
    }

    /// Debug aid: `DRAWER_SNAPSHOT=/path.png Drawer --show` renders the drawer to a PNG, then quits.
    func snapshot(to path: String) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func show(on screen: NSScreen, focus: Bool = false) {
        guard !isVisible else { return }
        isVisible = true
        scrollAccum = 0
        outsideSince = nil
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { AppModel.shared.previousApp = front }
        AppModel.shared.refresh()
        panel.appearance = settings.appearance.nsAppearance
        let f = screen.frame
        // Notched Macs report a top safe-area inset; push content below it.
        let inset = max(14, screen.safeAreaInsets.top + 6)
        AppModel.shared.layout.topInset = inset
        let h = settings.activeHeight + max(0, inset - 14)
        panel.setFrame(NSRect(x: f.minX, y: f.maxY, width: f.width, height: h), display: false)
        panel.orderFrontRegardless()
        // Come to the front as the active app, so shortcuts and mouse mappings tied to the app underneath
        // (Spotify, for instance) stop applying while the drawer is open.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h), display: true)
        }
    }

    /// Close the drawer. `done` runs once it is out of the way (used to paste into the app underneath).
    /// `restoreFocus` hands the front back to the app that was underneath, unless the pointer went to another app.
    func hide(then done: (() -> Void)? = nil, restoreFocus: Bool = true) {
        guard isVisible else { done?(); return }
        isVisible = false
        lastHide = Date()
        needsLeave = true
        scrollAccum = 0
        panel.makeFirstResponder(nil)
        var f = panel.frame
        f.origin.y += f.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            if self?.isVisible == false { self?.panel.orderOut(nil) }
            if done == nil, restoreFocus, let self, self.isVisible == false,
               NSWorkspace.shared.frontmostApplication == NSRunningApplication.current,
               let previous = AppModel.shared.previousApp,
               NSApp.windows.filter({ $0.isVisible && $0 !== self.panel && $0.canBecomeKey }).isEmpty {
                previous.activate(options: [])
            }
            done?()
        })
    }

    // MARK: Polling

    private func tick() {
        pollTriggers()
        guard isVisible, !stayOpen else { return }
        let inside = panel.frame.insetBy(dx: -24, dy: -24).contains(NSEvent.mouseLocation)
        // Take keyboard focus while the pointer is over the drawer so quick paste works; the app stays inactive.
        if inside, !panel.isKeyWindow { panel.makeKey() }
        // Never close while a button is held (dragging a file out) or while the user is typing.
        let typing = panel.firstResponder is NSTextView
        let delay = settings.autoHideSeconds
        if inside || AppModel.shared.popoverOpen || delay <= 0 || NSEvent.pressedMouseButtons != 0 || typing { outsideSince = nil; return }
        if outsideSince == nil { outsideSince = Date() }
        if Date().timeIntervalSince(outsideSince!) > delay { hide() }
    }

    /// "Hold a key" and "wait" openers: both look at the pointer resting on the top edge.
    private func pollTriggers() {
        guard let screen = screenUnderMouse() else { return }
        guard NSEvent.mouseLocation.y >= screen.frame.maxY - 2 else { edgeSince = nil; needsLeave = false; return }
        guard !isVisible, !needsLeave, NSEvent.pressedMouseButtons == 0 else { return }
        if edgeSince == nil { edgeSince = Date() }
        if settings.holdOpen, NSEvent.modifierFlags.contains(settings.holdModifier.flag) { show(on: screen); return }
        if settings.waitOpen, Date().timeIntervalSince(edgeSince!) >= settings.waitDelay { show(on: screen) }
    }
}
