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
        }.store(in: &cancellables)

        // Global mouse monitors need no Accessibility permission.
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] in self?.handleGlobalScroll($0) }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleLocalScroll(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleKey(event) ?? event }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.isVisible == true { self?.hide() }
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

    /// Accumulate swipes in one direction; returns true once the threshold is crossed.
    private func accumulate(_ amount: CGFloat) -> Bool {
        if Date().timeIntervalSince(lastScroll) > 0.3 { scrollAccum = 0 }
        lastScroll = Date()
        scrollAccum += amount
        return scrollAccum > 12
    }

    private func handleGlobalScroll(_ event: NSEvent) {
        // Momentum events trail a finished swipe; ignoring them stops the drawer reopening right after it closes.
        guard settings.scrollOpen, !isVisible, event.momentumPhase.isEmpty, Date().timeIntervalSince(lastHide) > 0.8,
              let screen = screenUnderMouse() else { return }
        guard NSEvent.mouseLocation.y >= screen.frame.maxY - 2 else { scrollAccum = 0; return }
        if accumulate(max(0, swipeDirection(event))) { show(on: screen) }
    }

    /// Scroll events over the drawer itself: a swipe up on its top strip closes it.
    private func handleLocalScroll(_ event: NSEvent) {
        guard isVisible, event.window === panel, event.momentumPhase.isEmpty else { return }
        let strip = AppModel.shared.layout.topInset + 36
        guard event.locationInWindow.y >= panel.frame.height - strip else { return }
        if accumulate(max(0, -swipeDirection(event))) { hide() }
    }

    // MARK: Keys

    /// Quick paste: modifier + 1…9 pastes the nth item in the list.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isVisible, settings.quickPaste, panel.isKeyWindow else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == settings.quickPasteModifier.flag, let ch = event.charactersIgnoringModifiers,
              let n = Int(ch), (1...9).contains(n) else { return event }
        let list = AppModel.shared.clipboard.visible
        if n <= list.count { AppModel.shared.use(list[n - 1]) }
        return nil
    }

    // MARK: Show and hide

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
        let h = settings.drawerHeight + max(0, inset - 14)
        panel.setFrame(NSRect(x: f.minX, y: f.maxY, width: f.width, height: h), display: false)
        panel.orderFrontRegardless()
        if focus { panel.makeKey() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h), display: true)
        }
    }

    /// Close the drawer. `done` runs once it is out of the way (used to paste into the app underneath).
    func hide(then done: (() -> Void)? = nil) {
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
        if inside || delay <= 0 || NSEvent.pressedMouseButtons != 0 || typing { outsideSince = nil; return }
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
