import AppKit
import SwiftUI

// Drawer extras around select mode: the group switcher in the header, the empty state when filters hide everything,
// ⇧-arrow selection, and dragging several picked items out at once.

// MARK: Group switcher

/// The ★ in the drawer header: everything, pins only, pins in no group, or one group.
struct GroupSwitcher: View {
    @ObservedObject var store: ClipboardStore
    @StateObject private var hovering = Box(false)

    var body: some View {
        let active = store.pinnedOnly || store.groupFilter != nil
        let symbol = store.groupFilter.map { $0.isEmpty ? "pin.fill" : "square.stack.fill" } ?? (store.pinnedOnly ? "star.fill" : "star")
        Menu {
            CheckButton("All Items", !active) { store.pinnedOnly = false; store.groupFilter = nil }
            CheckButton("Pinned Only", store.pinnedOnly && store.groupFilter == nil) { store.pinnedOnly = true; store.groupFilter = nil }
            CheckButton("Pins in No Group", store.groupFilter == "") { store.pinnedOnly = false; store.groupFilter = "" }
            if !store.groups.isEmpty { Divider() }
            ForEach(store.groups, id: \.self) { name in
                CheckButton(name, store.groupFilter == name) { store.pinnedOnly = false; store.groupFilter = name }
            }
            Divider()
            Button("New Group…") { withAnimation { store.naming = .init() } }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: fs(12), weight: .medium))
                .foregroundStyle(active ? Color.accentColor : (hovering.value ? Color.primary : Color.secondary))
                .frame(width: 26, height: 26)
                .background(hovering.value ? Color.primary.opacity(0.14) : (active ? Color.primary.opacity(0.08) : .clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
        .onHover { hovering.value = $0 }
        .help(store.groupFilter.map { $0.isEmpty ? "Showing pins in no group" : "Showing \($0)" } ?? (store.pinnedOnly ? "Showing pinned only" : "Pinned and groups"))
        .accessibilityLabel("Pinned and groups")
    }
}

// MARK: Empty because of filters

extension ClipboardStore {
    /// Everything that narrows the drawer list now, for the empty state: filters, the group switcher and the search.
    var narrowingSummary: String? {
        var parts: [String] = []
        if let s = filterSummary { parts.append(s) }
        if let g = groupFilter { parts.append(g.isEmpty ? "pins in no group" : "the group “\(g)”") }
        else if pinnedOnly { parts.append("pinned only") }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { parts.append("“\(q)”") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Back to the whole history: no filters, no group, no search.
    func showEverything() {
        clearFilters()
        groupFilter = nil
        pinnedOnly = false
        query = ""
        searching = false
    }
}

/// What the drawer says when the filters leave nothing to show, with one button to undo them.
struct FilteredEmptyState: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: fs(22))).foregroundStyle(.tertiary)
            Text("Nothing matches").font(.system(size: fs(12.5), weight: .semibold)).foregroundStyle(.secondary)
            if let summary = store.narrowingSummary {
                Text("Showing \(summary).").font(.system(size: fs(11.5))).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 20)
            }
            Button { store.showEverything() } label: { DrawerPill(title: "Show Everything", symbol: "xmark.circle") }
                .buttonStyle(.plain).padding(.top, 2)
        }
    }
}

// MARK: ⇧-arrow selection

extension ClipboardStore {
    /// The selection a ⇧-arrow run makes: what was picked before the run, plus every item from where it started to the cursor.
    static func extended(_ base: Set<UUID>, anchor: UUID, to cursor: UUID, in order: [UUID]) -> Set<UUID> {
        base.union(run(from: anchor, to: cursor, in: order) ?? [cursor])
    }
}

/// Remembers a ⇧-arrow run between key presses. A click or any other change of selection starts a new run.
final class KeySelect {
    private var base: Set<UUID>?
    private var anchor: UUID?
    private var last: Set<UUID>?

    func reset() { base = nil; anchor = nil; last = nil }

    /// ⇧ with an arrow: enters select mode if needed and grows (or, moving back, shrinks) the run from its start.
    func extend(_ delta: Int, store: ClipboardStore) {
        let order = store.window.map(\.id)
        guard !order.isEmpty else { return }
        if base == nil || anchor == nil || !store.selecting || store.selection != last {
            // A new run starts at the item under the cursor, or at one end when nothing has the cursor yet.
            let had = store.cursor.flatMap { order.contains($0) ? $0 : nil }
            let start = had ?? (delta > 0 ? order.first! : order.last!)
            if !store.selecting { store.beginSelecting() }
            base = store.selection
            anchor = start
            store.cursor = start
            if had == nil {
                store.selection.insert(start)
                store.selectionAnchor = start
                last = store.selection
                return
            }
        }
        store.moveCursor(delta)
        guard let anchor, let cursor = store.cursor else { return }
        store.selection = ClipboardStore.extended(base ?? [], anchor: anchor, to: cursor, in: order)
        store.selectionAnchor = anchor
        last = store.selection
    }
}

// MARK: Dragging several items out

/// Starts one drag that carries every picked item: text as text, pictures and files as their files. AppKit does this with
/// several dragging items in one session, which SwiftUI's `onDrag` (one item provider) cannot do before macOS 26.
/// It has to run while AppKit is handling a mouse-dragged event, so it is called from a drag gesture's first change.
enum MultiDrag {
    private static let source = Source()

    final class Source: NSObject, NSDraggingSource {
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }

    /// What each item puts on the drag pasteboard. Sensitive items are never dragged out.
    static func writers(for clips: [Clip]) -> [NSPasteboardWriting] {
        clips.filter { !$0.sensitive }.flatMap { clip -> [NSPasteboardWriting] in
            switch clip.kind {
            case .text: return (clip.text?.isEmpty == false) ? [clip.text! as NSString] : []
            case .image: return clip.imageURL.map { [$0 as NSURL] } ?? []
            case .file: return clip.fileURLs.map { $0 as NSURL }
            }
        }
    }

    @discardableResult
    static func begin(_ clips: [Clip]) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return false }
        let writers = writers(for: clips)
        guard !writers.isEmpty else { return false }
        let p = view.convert(event.locationInWindow, from: nil)
        let items = writers.enumerated().map { n, writer -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: writer)
            let offset = CGFloat(min(n, 4)) * 5
            item.setDraggingFrame(NSRect(x: p.x - 24 + offset, y: p.y - 24 - offset, width: 48, height: 48), contents: icon(for: writer))
            return item
        }
        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.draggingFormation = .stack
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    private static func icon(for writer: NSPasteboardWriting) -> NSImage {
        if let url = writer as? NSURL, let path = url.path { return NSWorkspace.shared.icon(forFile: path) }
        let img = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
        return img.withSymbolConfiguration(.init(pointSize: 30, weight: .medium)) ?? img
    }
}
