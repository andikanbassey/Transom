import AppKit
import Combine

// Pasting several items: joined into one (Paste Together), or one after another (the paste stack). The joining rules are
// plain functions so they can be tested; the stack watches for ⌘V and puts the next item on the clipboard after each paste.

/// How several items become one piece of text, and in which order.
enum Joining {
    /// "Copy order" sorts oldest first; "Order picked" keeps the order given.
    static func ordered(_ items: [Clip], by order: JoinOrder) -> [Clip] {
        order == .copied ? items.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }.map(\.element) : items
    }

    /// The text of the text items, joined. Pictures, files and sensitive items are left out; nil when nothing is left.
    static func text(_ items: [Clip], separator: JoinSeparator) -> String? {
        let texts = items.filter { $0.kind == .text && !$0.sensitive }.compactMap(\.text)
        return texts.isEmpty ? nil : texts.joined(separator: separator.string)
    }
}

/// Paste One by One: the first item goes on the clipboard, and each ⌘V moves the next one onto it, until the last has been
/// pasted, the user copies something else, or they stop it from the menu bar.
final class PasteStack: ObservableObject {
    static let shared = PasteStack()

    /// The items in the order they are pasted, and which one is on the clipboard now.
    @Published private(set) var items: [Clip] = []
    @Published private(set) var position = 0

    var isActive: Bool { !items.isEmpty }
    /// "2/5": the item on the clipboard now, out of all.
    var progress: String { "\(position + 1)/\(items.count)" }

    private var monitors: [Any] = []
    private var expectedChange = 0
    private var watch: Timer?
    private var advancing = false

    /// Starts a stack. Needs the Accessibility permission (to see ⌘V in other apps); without it, asks for it and does nothing.
    @discardableResult
    func start(_ clips: [Clip], order: JoinOrder = Settings.shared.v.joinOrder) -> Bool {
        let queue = Self.queue(clips, order: order)
        guard !queue.isEmpty else { NSSound.beep(); return false }
        guard Paster.trusted else { Paster.requestTrust(); return false }
        stop()
        items = queue
        position = 0
        put(items[0])
        let onKey: (NSEvent) -> Void = { [weak self] e in self?.keyDown(e) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKey) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { onKey($0); return $0 }) { monitors.append(l) }
        // Anything else landing on the clipboard (the user copied something) ends the stack.
        watch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.advancing, NSPasteboard.general.changeCount != self.expectedChange else { return }
            self.stop()
        }
        if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
        return true
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        watch?.invalidate()
        watch = nil
        items = []
        position = 0
        advancing = false
    }

    /// Skips the item on the clipboard now without pasting it.
    func skip() { advance() }

    /// The items a stack pastes, in order: sensitive items are left out (they are not exported), so is anything empty.
    static func queue(_ clips: [Clip], order: JoinOrder) -> [Clip] {
        Joining.ordered(clips, by: order).filter { clip in
            guard !clip.sensitive else { return false }
            switch clip.kind {
            case .text: return !(clip.text ?? "").isEmpty
            case .image: return clip.imageFile != nil
            case .file: return !(clip.paths ?? []).isEmpty
            }
        }
    }

    /// Where a stack goes after a paste: the next position, or nil when the last item has been pasted.
    static func next(after position: Int, count: Int) -> Int? {
        position + 1 < count ? position + 1 : nil
    }

    private func keyDown(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        guard isActive, flags == .command, e.charactersIgnoringModifiers?.lowercased() == "v", !advancing else { return }
        // The app reads the clipboard while it handles the key; give it a moment before the next item replaces it.
        advancing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.advance() }
    }

    private func advance() {
        guard isActive else { return }
        guard let n = Self.next(after: position, count: items.count) else { stop(); return }
        position = n
        put(items[n])
        advancing = false
    }

    /// Puts one item on the clipboard the way a click does (the store skips recording it as a new copy).
    private func put(_ clip: Clip) {
        let store = AppModel.shared.clipboard
        store.copy(store.clips.first { $0.id == clip.id } ?? clip)
        expectedChange = NSPasteboard.general.changeCount
    }
}
