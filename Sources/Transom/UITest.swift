import AppKit
import Carbon.HIToolbox
import SwiftUI

// Debug aid: TRANSOM_UI_TEST=1 drives the real app with posted key presses and mouse drags (Transom has the Accessibility
// permission this needs) and writes what happened to /tmp/transom-ui-test.txt. Run it on scratch data only, with the everyday
// Transom quit, from /Applications so macOS uses the app's own permission:
//   open -n -a /Applications/Transom.app --env TRANSOM_UI_TEST=1 --env TRANSOM_SUPPORT_DIR=/tmp/transom-ui-<unique>
// It needs at least six unpinned text items and a group called "Replies" (see CLAUDE.md). It takes over the keyboard and
// mouse for about a minute.

/// Where marked views are on screen, in SwiftUI's window coordinates. Only filled while the UI test runs.
final class TestFrames {
    static let shared = TestFrames()
    static let enabled = Env["UI_TEST"] != nil
    var frames: [String: CGRect] = [:]
}

extension View {
    /// Records this view's frame for the UI test under `key`; does nothing otherwise.
    @ViewBuilder func testFrame(_ key: String) -> some View {
        if TestFrames.enabled {
            background(GeometryReader { g in
                Color.clear
                    .onAppear { TestFrames.shared.frames[key] = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in TestFrames.shared.frames[key] = f }
            })
        } else {
            self
        }
    }
}

/// A window that takes drops and remembers what arrived, standing in for Finder or Notes in the drag test.
private final class DropView: NSView {
    var received: [String] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string, .fileURL, .png, .tiff])
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.3).cgColor
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        received = (sender.draggingPasteboard.pasteboardItems ?? []).map { item in
            item.string(forType: .fileURL).map { "file:" + (URL(string: $0)?.lastPathComponent ?? $0) } ?? item.string(forType: .string) ?? "(\(item.types.map(\.rawValue).joined(separator: ",")))"
        }
        return true
    }
}

@MainActor
final class UITest {
    private var lines: [String] = []
    private var failures = 0
    private let store = AppModel.shared.clipboard
    private let src = CGEventSource(stateID: .hidSystemState)
    private let out = "/tmp/transom-ui-test.txt"

    static func start(drawer: TransomController) {
        Task { @MainActor in await UITest().run(drawer: drawer) }
    }

    private func log(_ s: String) {
        lines.append(s)
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
    }

    private func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    private weak var drawerRef: TransomController?
    private var state: String {
        "front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-") open=\(drawerRef?.isVisible ?? false) key=\(NSApp.keyWindow is TransomPanel) " + "selecting=\(store.selecting) picked=\(store.selection.count) cursor=\(store.cursor.flatMap { id in store.window.firstIndex { $0.id == id } }.map(String.init) ?? "-") pendingDelete=\(store.pendingDelete?.count ?? 0) undo=\(store.undoable?.clips.count ?? 0) items=\(store.clips.count)"
    }

    // MARK: Input

    /// Which app must be in front for keys to be posted: posting into the wrong app (a terminal, say) could do harm there.
    private var expectFront = Bundle.main.bundleIdentifier ?? ""
    private var aborted = false

    private func key(_ code: Int, _ flags: CGEventFlags = []) async {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        guard !aborted, front == expectFront else {
            if !aborted { aborted = true; check("expected \(expectFront) in front before posting keys", false, "front is \(front); stopped posting") }
            return
        }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        await wait(0.35)
    }

    private func mouse(_ type: CGEventType, _ p: CGPoint, _ flags: CGEventFlags = []) {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    private func drag(_ a: CGPoint, _ b: CGPoint, flags: CGEventFlags = [], steps: Int = 24) async {
        mouse(.mouseMoved, a)
        await wait(0.2)
        mouse(.leftMouseDown, a, flags)
        await wait(0.25)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags)
            await wait(0.03)
        }
        await wait(0.3)
        mouse(.leftMouseUp, b, flags)
        await wait(0.6)
    }

    /// The centre of a marked view, in the screen coordinates posted events use (top left of the main screen is 0,0).
    private func point(_ key: String, in window: NSWindow?) -> CGPoint? {
        guard let window, let f = TestFrames.shared.frames[key] else { return nil }
        let height = window.contentView?.frame.height ?? window.frame.height
        let cocoa = CGPoint(x: window.frame.minX + f.midX, y: window.frame.minY + height - f.midY)
        return CGPoint(x: cocoa.x, y: NSScreen.screens[0].frame.height - cocoa.y)
    }

    // MARK: Run

    private func run(drawer: TransomController) async {
        drawerRef = drawer
        log("Transom UI test \(Date())  trusted=\(Paster.trusted)")
        guard Paster.trusted else { log("FAIL  Transom has no Accessibility permission, so it cannot post events"); finish(); return }
        for _ in 0..<100 where store.loading { await wait(0.1) }
        Settings.shared.v.clipboardCards = true
        Settings.shared.v.pasteMode = .clipboard
        Settings.shared.v.sounds = false

        await keys(drawer)
        await dragSelect(drawer)
        await pasteStack(drawer)
        await libraryDrop()
        finish()
    }

    private func finish() {
        log(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    /// ⇧-arrows, Space, Esc, Delete, Return, ⌘Z and plain arrows in the drawer.
    private func keys(_ drawer: TransomController) async {
        log("\n— Keys in the drawer")
        if !drawer.isVisible { drawer.toggle() }
        NSApp.activate(ignoringOtherApps: true)
        await wait(1.5)
        expectFront = Bundle.main.bundleIdentifier ?? ""
        store.cursor = nil
        log("start: \(state)")
        await key(kVK_RightArrow)
        await key(kVK_RightArrow)
        check("→ moves the cursor", store.cursor == store.window.dropFirst(1).first?.id, state)
        await key(kVK_RightArrow, .maskShift)
        await key(kVK_RightArrow, .maskShift)
        check("⇧→ twice starts select mode and picks a run", store.selecting && store.selection.count >= 2, state)
        let before = store.selection.count
        await key(kVK_Space)
        check("Space flips the item under the cursor", store.selection.count == before - 1, state)
        await key(kVK_Escape)
        check("Esc leaves select mode", !store.selecting && store.selection.isEmpty, state)

        let count = store.clips.count
        await key(kVK_RightArrow, .maskShift)
        let picked = store.selection.count
        check("⇧→ from the cursor picks again", store.selecting && picked >= 1, state)
        await key(kVK_Delete)
        check("Delete asks first", store.pendingDelete?.count == picked, state)
        await key(kVK_Return)
        check("Return confirms: items leave the list, Undo is offered", store.clips.count == count - picked && store.undoable?.clips.count == picked, state)
        await key(kVK_ANSI_Z, .maskCommand)
        check("⌘Z brings them back", store.clips.count == count && store.undoable == nil, state)
        await key(kVK_ANSI_A, .maskCommand)
        check("⌘A picks everything shown", store.selecting && store.selection.count == store.window.count, state)
        await key(kVK_Escape)
    }

    /// Drag across cards to pick, ⌥-drag to unpick, then drag picked cards out into another window.
    private func dragSelect(_ drawer: TransomController) async {
        log("\n— Dragging in the drawer")
        if !drawer.isVisible { drawer.toggle(); await wait(1.2) }
        let panel = NSApp.windows.first { $0 is TransomPanel }
        let ids = store.window.filter { !$0.pinned }.prefix(4).map(\.id)
        store.beginSelecting()
        store.selection = []
        await wait(0.8)
        guard ids.count == 4, let a = point("card:\(ids[0])", in: panel), let d = point("card:\(ids[3])", in: panel),
              let b = point("card:\(ids[1])", in: panel) else {
            check("cards found on screen", false, "frames: \(TestFrames.shared.frames.keys.filter { $0.hasPrefix("card:") }.count)")
            return
        }
        await drag(a, d)
        check("dragging across four cards picks them", Set(ids).isSubset(of: store.selection), state)
        await drag(b, a, flags: .maskAlternate)
        check("⌥-drag unpicks", !store.selection.contains(ids[0]) && !store.selection.contains(ids[1]), state)

        // Drag the picked ones out to a stand-in window.
        let target = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 360, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        target.title = "Drop Target"
        let view = DropView(frame: target.contentLayoutRect)
        target.contentView = view
        target.level = .floating
        target.orderFrontRegardless()
        await wait(0.6)
        let picked = store.selectedClips
        guard let c = point("card:\(ids[2])", in: panel) else { return }
        let dest = CGPoint(x: 260, y: NSScreen.screens[0].frame.height - 210)
        await drag(c, dest, steps: 40)
        await wait(0.8)
        check("dragging a picked card carries all picked items out", view.received.count == picked.count,
              "sent \(picked.count), received \(view.received.count): \(view.received.map { String($0.prefix(24)) })")
        target.orderOut(nil)
        store.endSelecting()
    }

    /// Paste One by One into TextEdit: each ⌘V pastes the next item.
    private func pasteStack(_ drawer: TransomController) async {
        log("\n— Paste One by One")
        let items = Array(store.window.filter { !$0.pinned && $0.kind == .text }.prefix(3))
        guard items.count == 3 else { check("three text items", false); return }
        let file = URL(fileURLWithPath: "/tmp/transom-ui-paste.txt")
        try? "".write(to: file, atomically: true, encoding: .utf8)
        guard PasteStack.shared.start(items, order: .copied) else { check("stack starts", false); return }
        if drawer.isVisible { drawer.toggle() }
        guard let edit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { check("TextEdit found", false); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.open([file], withApplicationAt: edit, configuration: config)
        await wait(2.5)
        expectFront = "com.apple.TextEdit"
        aborted = false
        let expected = items.sorted { $0.date < $1.date }.compactMap(\.text)
        var seen: [String] = []
        for _ in 0..<3 {
            seen.append(NSPasteboard.general.string(forType: .string) ?? "")
            await key(kVK_ANSI_V, .maskCommand)
            await wait(0.7)
        }
        check("each ⌘V put the next item on the clipboard", seen == expected, "clipboard was \(seen.map { String($0.prefix(20)) })")
        check("the stack ended after the last item", !PasteStack.shared.isActive)
        await key(kVK_ANSI_S, .maskCommand)
        await wait(1.0)
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check("TextEdit received all three, in order", text == expected.joined(), "file has \(text.count) characters: \(String(text.prefix(60)))")
        await key(kVK_ANSI_W, .maskCommand)
        await wait(0.6)
        expectFront = Bundle.main.bundleIdentifier ?? ""
        aborted = false
    }

    /// Drag a Library card onto the "Replies" group in the sidebar.
    private func libraryDrop() async {
        log("\n— Library: drop a card on a group")
        MainNav.shared.section = .clipboard
        SettingsWindow.shared.show(tab: .library)
        await wait(2.5)
        let window = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.title != "Drop Target" && $0.frame.width > 600 }
        guard let clip = store.clips.first(where: { !$0.pinned && $0.kind == .text }),
              let from = point("libcard:\(clip.id)", in: window), let to = point("group:Replies", in: window) else {
            check("card and group found on screen", false, "window=\(window != nil) frames=\(TestFrames.shared.frames.keys.filter { !$0.hasPrefix("card:") })")
            return
        }
        await drag(from, to, steps: 40)
        await wait(0.8)
        let now = store.clips.first { $0.id == clip.id }
        check("the card is now in Replies, pinned", now?.pinGroup == "Replies", "group=\(now?.group ?? "nil") pinned=\(now?.pinned ?? false)")
    }
}

