import AppKit
import SwiftUI

// Select mode in the drawer (pick several clipboard items, then pin, group, copy or delete them together), the group menus
// shared with the Library, and the right-click items that follow the selection and the filters.

extension ClipboardStore {
    /// The picked items that still exist.
    var selectedClips: [Clip] { clips.filter { selection.contains($0.id) } }

    /// The picked items in the order they were picked; any picked in bulk (Select All) follow in the order shown.
    var pickedInOrder: [Clip] {
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Self.pickOrder(selection, recorded: selectionOrder, shown: window.map(\.id)).compactMap { byID[$0] }
    }

    /// The order behind `pickedInOrder`, on its own so it can be tested.
    static func pickOrder(_ selection: Set<UUID>, recorded: [UUID], shown: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        let first = recorded.filter { selection.contains($0) && seen.insert($0).inserted }
        let rest = (shown + Array(selection)).filter { selection.contains($0) && seen.insert($0).inserted }
        return first + rest
    }

    /// Notes ids as picked, for "Order picked".
    func recordPicked(_ ids: [UUID]) {
        selectionOrder.removeAll { ids.contains($0) }
        selectionOrder += ids
    }

    func beginSelecting(_ id: UUID? = nil) {
        selecting = true
        cursor = nil
        expanded = nil
        if let id { selection.insert(id); selectionAnchor = id; recordPicked([id]) }
    }

    func endSelecting() {
        selecting = false
        selection = []
        selectionOrder = []
        selectionAnchor = nil
        pendingDelete = nil
    }

    /// A click on an item while selecting: on its own it flips that item; with ⇧ it adds everything from the last click to this one.
    func clickSelect(_ id: UUID, extend: Bool) {
        if extend, let anchor = selectionAnchor, let run = Self.run(from: anchor, to: id, in: window.map(\.id)) {
            recordPicked(run.first == anchor ? run : Array(run.reversed()))
            selection.formUnion(run)
            return
        }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id); recordPicked([id]) }
        selectionAnchor = id
    }

    /// The items from `a` to `b` inclusive, in either direction, or nil if one of them is not in `order`.
    static func run(from a: UUID, to b: UUID, in order: [UUID]) -> [UUID]? {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return nil }
        return Array(order[min(i, j)...max(i, j)])
    }

    func selectAllShown() {
        beginSelecting()
        selection = Set(window.map(\.id))
    }

    /// Adds the shown items copied in the last `seconds` to the selection.
    func selectRecent(_ seconds: TimeInterval) {
        beginSelecting()
        let cutoff = Date().addingTimeInterval(-seconds)
        selection.formUnion(window.filter { $0.date >= cutoff }.map(\.id))
    }

    func invertSelection() {
        selection = Set(window.map(\.id)).subtracting(selection)
    }

    /// True when every picked item that can be pinned already is: the batch button then says Unpin.
    var selectionAllPinned: Bool {
        let pinnable = selectedClips.filter { !$0.sensitive }
        return !pinnable.isEmpty && pinnable.allSatisfy(\.pinned)
    }

    func pinSelection() {
        setPinned(!selectionAllPinned, ids: selection)
    }

    /// Copies the picked items as one and, in the drawer, pastes them into the app underneath.
    func useSelection(paste: Bool) {
        let items = pickedInOrder
        guard copyTogether(items) else { NSSound.beep(); return }
        endSelecting()
        if paste { AppModel.shared.pasteCurrent() } else if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
    }

    /// Paste One by One: the picked items go onto the clipboard one at a time, the next after each ⌘V. Closes the drawer.
    func pasteOneByOne() {
        guard PasteStack.shared.start(pickedInOrder) else { return }
        endSelecting()
        AppModel.shared.hideDrawer()
    }

    /// Asks before deleting (at the bottom of the panel, so the drawer stays open).
    func askDeleteSelection() {
        guard !selection.isEmpty else { return }
        withAnimation { pendingDelete = Set(selectedClips.map(\.id)) }
    }

    /// What the filters narrow the list to, for menu headers: "Ghostty", "Images from Ghostty", "Today".
    var filterSummary: String? {
        guard isFiltered else { return nil }
        let app = appFilter.flatMap { key in appsInHistory.first { $0.key == key }?.name }
        let type = filter == .all ? nil : filter.rawValue
        let when = time == .any ? nil : time.rawValue
        switch (type, app) {
        case let (t?, a?): return [t + " from " + a, when].compactMap { $0 }.joined(separator: " · ")
        default: return [type ?? app, when].compactMap { $0 }.joined(separator: " · ")
        }
    }

    func clearFilters() {
        filter = .all
        time = .any
        appFilter = nil
    }
}

/// The round check in a card's corner or at a row's edge: empty while it could be picked, filled once it is.
struct SelectCircle: View {
    let on: Bool
    var size: CGFloat = 18

    var body: some View {
        // Picked: a white disc with an accent tick, which reads on every card colour as well as on a plain row.
        ZStack {
            Circle().fill(on ? Color.white : Color.black.opacity(0.25))
            Circle().strokeBorder(on ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.95), lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: size * 0.52, weight: .heavy)).foregroundStyle(Color.accentColor) }
        }
        .shadow(color: .black.opacity(on ? 0.25 : 0), radius: 2, y: 1)
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Where each card or row sits while selecting, so a drag across them can pick everything it passes.
struct ClipFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Drag-to-select bookkeeping. Not published: a drag changes the store's selection, and that redraws what needs it.
final class DragSelect: ObservableObject {
    var frames: [UUID: CGRect] = [:]
    var base: Set<UUID>?
    var start: UUID?
    var adding = true

    /// The item under the point, or the nearest one when the point is in a gap between them.
    func item(at p: CGPoint) -> UUID? {
        frames.min { distance($0.value, p) < distance($1.value, p) }?.key
    }

    private func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}

extension View {
    /// Reports this item's frame for drag-to-select, only while selecting.
    @ViewBuilder func selectFrame(_ id: UUID, active: Bool) -> some View {
        if active {
            background(GeometryReader { g in
                Color.clear.preference(key: ClipFrames.self, value: [id: g.frame(in: .named(DrawerSelect.space))])
            })
        } else {
            self
        }
    }

    /// Drag the item out into another app, except while selecting, when a drag picks items instead.
    @ViewBuilder func dragOut(_ clip: Clip, enabled: Bool) -> some View {
        if enabled { onDrag { dragProvider(clip) } } else { self }
    }

    /// A drag across the cards or rows picks (or, starting on a picked one, unpicks) every item between start and pointer.
    func dragToSelect(store: ClipboardStore, state: DragSelect) -> some View {
        coordinateSpace(name: DrawerSelect.space)
            .onPreferenceChange(ClipFrames.self) { state.frames = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(DrawerSelect.space))
                    .onChanged { g in
                        guard store.selecting, let start = state.start ?? state.item(at: g.startLocation),
                              let now = state.item(at: g.location) else { return }
                        if state.base == nil {
                            state.base = store.selection
                            state.start = start
                            state.adding = !store.selection.contains(start)
                        }
                        let order = store.window.map(\.id)
                        guard let run = ClipboardStore.run(from: start, to: now, in: order) else { return }
                        let base = state.base ?? []
                        store.selection = state.adding ? base.union(run) : base.subtracting(run)
                        if state.adding { store.recordPicked(run.first == start ? run : Array(run.reversed())) }
                        store.selectionAnchor = now
                    }
                    .onEnded { _ in state.base = nil; state.start = nil },
                including: store.selecting ? .all : .subviews
            )
    }
}

enum DrawerSelect {
    static let space = "drawerSelect"
}

/// A compact pill for the drawer's selection bar: the size of the filter buttons it replaces.
struct DrawerPill: View {
    let title: String
    var symbol: String?
    var tint: Color?
    var filled = false
    var chevron = false
    var iconOnly = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: fs(10.5), weight: .semibold)) }
            if !iconOnly || symbol == nil { Text(title).font(.system(size: fs(11.5), weight: .medium)).lineLimit(1) }
            if chevron { Image(systemName: "chevron.down").font(.system(size: fs(7), weight: .bold)).opacity(0.7) }
        }
        .foregroundStyle(filled ? Color.white : (tint ?? Color.primary.opacity(0.85)))
        .padding(.horizontal, iconOnly ? 8 : 10).frame(height: 26)
        .background(filled ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The drawer header while selecting: the count, the batch actions, then Select and Done.
struct DrawerSelectionBar: View {
    @ObservedObject var store: ClipboardStore
    let width: CGFloat

    var body: some View {
        let items = store.selectedClips
        let n = items.count
        let narrow = width < 640
        HStack(spacing: 6) {
            Button { store.selection = [] } label: {
                Image(systemName: "xmark").font(.system(size: fs(9), weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain).disabled(n == 0).opacity(n == 0 ? 0.4 : 1).help("Clear selection").accessibilityLabel("Clear selection")
            Text(n == 0 ? "Select items" : "\(n) selected").font(.system(size: fs(12.5), weight: .semibold)).foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            Group {
                Button { store.pinSelection() } label: {
                    DrawerPill(title: store.selectionAllPinned ? "Unpin" : "Pin", symbol: store.selectionAllPinned ? "pin.slash" : "pin", iconOnly: narrow)
                }
                .buttonStyle(.plain)
                Menu { GroupMenuItems(store: store, ids: Set(items.map(\.id))) } label: {
                    DrawerPill(title: "Group", symbol: "square.stack", chevron: true, iconOnly: narrow)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
                Menu {
                    Button("Paste Together") { store.useSelection(paste: true) }
                        .disabled(!items.contains { $0.kind != .image && !$0.sensitive })
                    Button("Paste One by One") { store.pasteOneByOne() }
                    Divider()
                    JoinOptions()
                } label: { DrawerPill(title: "Paste", symbol: "doc.on.clipboard", chevron: true, iconOnly: narrow) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
                Button { store.askDeleteSelection() } label: { DrawerPill(title: "Delete", symbol: "trash", tint: .red, iconOnly: narrow) }
                    .buttonStyle(.plain)
            }
            .disabled(n == 0).opacity(n == 0 ? 0.45 : 1)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 2)
            Menu { SelectChoices(store: store) } label: { DrawerPill(title: "Select", symbol: "checklist", chevron: true, iconOnly: narrow) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
            Button { store.endSelecting() } label: { DrawerPill(title: "Done", filled: true) }
                .buttonStyle(.plain).help("Done (Esc)")
        }
    }
}

/// Quick ways to pick: everything shown, by age, the opposite, or nothing.
struct SelectChoices: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        Button("All Shown (\(store.window.count))") { store.selectAllShown() }
        Divider()
        Button("Last 5 Minutes") { store.selectRecent(300) }
        Button("Last Hour") { store.selectRecent(3600) }
        Button("Today") { store.selectRecent(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))) }
        Divider()
        Button("Invert Selection") { store.invertSelection() }
        Button("None") { store.selection = [] }
    }
}

/// "Move to Group": every group (ticked when all the items are in it), a new one, or out of their group.
struct GroupMenuItems: View {
    @ObservedObject var store: ClipboardStore
    let ids: Set<UUID>
    var done: () -> Void = {}

    var body: some View {
        let items = store.clips.filter { ids.contains($0.id) && !$0.sensitive }
        ForEach(store.groups, id: \.self) { name in
            CheckButton(name, !items.isEmpty && items.allSatisfy { $0.pinGroup == name }) { store.setGroup(name, ids: ids); done() }
        }
        if !store.groups.isEmpty { Divider() }
        Button("New Group…") { withAnimation { store.naming = .init(ids: ids) } }
        if items.contains(where: { $0.pinGroup != nil }) {
            Button("Remove from Group") { store.setGroup(nil, ids: ids); done() }
        }
    }
}

/// Right-click items for the picked items, wherever the right-click lands.
struct SelectionMenuItems: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        let items = store.selectedClips
        let n = items.count
        Section("\(n) Selected") {
            Button("Paste Together") { store.useSelection(paste: true) }.disabled(!items.contains { $0.kind != .image && !$0.sensitive })
            Button("Copy Together") { store.useSelection(paste: false) }.disabled(!items.contains { $0.kind != .image && !$0.sensitive })
            Button("Paste One by One") { store.pasteOneByOne() }
            Menu("Paste Options") { JoinOptions() }
            Button(store.selectionAllPinned ? "Unpin \(n == 1 ? "Item" : "\(n) Items")" : "Pin \(n == 1 ? "Item" : "\(n) Items")") { store.pinSelection() }
            Menu("Move to Group") { GroupMenuItems(store: store, ids: Set(items.map(\.id))) }
            Button("Delete \(n == 1 ? "Item" : "\(n) Items")…") { store.askDeleteSelection() }
        }
        Divider()
        Menu("Select") { SelectChoices(store: store) }
        Button("Done Selecting") { store.endSelecting() }
    }
}

/// Right-click items for the list as it is filtered now: pick or clear what the filters show, or stop recording that app.
struct ClipboardScopeItems: View {
    @ObservedObject var store: ClipboardStore
    /// What "Select" does here: the drawer's select mode by default, the Library's in the Library.
    var selectAll: (() -> Void)?
    var startSelecting: (() -> Void)?
    /// How many items the page shows, when that is not the drawer's list.
    var shown: Int?

    var body: some View {
        if let scope = store.filterSummary {
            let n = shown ?? store.window.count
            Section(scope) {
                Button("Select All \(n) Shown") { (selectAll ?? store.selectAllShown)() }
                    .disabled(n == 0)
                ClearUnpinnedButton(store: store)
                if let key = store.appFilter, let app = store.appsInHistory.first(where: { $0.key == key }) {
                    Button("Never Record from \(app.name)") {
                        Settings.shared.block(AppRef(bundleID: app.bundle ?? key, name: app.name))
                        Settings.shared.v.captureMode = .blockList
                    }
                }
                Button("Show Everything") { store.clearFilters() }
            }
        } else {
            Button("Select Items") { (startSelecting ?? { store.beginSelecting() })() }.disabled(store.clips.isEmpty)
            ClearUnpinnedButton(store: store)
        }
    }
}

/// The right-click menu on empty space in the clipboard panel: the selection first, then the filters, then the app menu.
struct ClipboardPanelMenu: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        if store.selecting && !store.selection.isEmpty {
            SelectionMenuItems(store: store)
        } else {
            ClipboardScopeItems(store: store)
        }
        Divider()
        AppMenuItems()
    }
}

/// Typing a group's name, at the bottom of the panel so the drawer stays open.
struct GroupNameBar: View {
    @ObservedObject var store: ClipboardStore
    @StateObject private var name = Box("")
    @FocusState private var focused: Bool

    var body: some View {
        if let naming = store.naming {
            let renaming = naming.renaming
            HStack(spacing: 10) {
                Image(systemName: "square.stack").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField(renaming == nil ? "New group name" : "Rename “\(renaming!)”", text: $name.value)
                    .textFieldStyle(.plain).font(.system(size: 12.5, weight: .medium))
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { cancel() }
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12, weight: .medium))
                Button(renaming == nil ? (naming.ids.isEmpty ? "Create" : "Create and Move") : "Rename", action: commit)
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4).background(Color.accentColor, in: Capsule())
                    .disabled(name.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .padding(.horizontal, 14).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                name.value = renaming ?? ""
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private func commit() {
        guard let naming = store.naming else { return }
        let new = name.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return }
        if let old = naming.renaming {
            store.renameGroup(old, to: new)
        } else if naming.ids.isEmpty {
            store.addGroup(new)
        } else {
            store.setGroup(new, ids: naming.ids)
            store.endSelecting()
        }
        cancel()
    }

    private func cancel() {
        withAnimation { store.naming = nil }
        name.value = ""
    }
}

/// The separator and order for Paste Together and Paste One by One, as ticked menu items (also in Settings › Clipboard).
struct JoinOptions: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Section("Between items") {
            ForEach(JoinSeparator.allCases, id: \.self) { sep in
                CheckButton(sep.label, settings.v.joinSeparator == sep) { settings.v.joinSeparator = sep }
            }
        }
        Section("Order") {
            CheckButton("Copy Order", settings.v.joinOrder == .copied) { settings.v.joinOrder = .copied }
            CheckButton("Order Picked", settings.v.joinOrder == .picked) { settings.v.joinOrder = .picked }
        }
    }
}
