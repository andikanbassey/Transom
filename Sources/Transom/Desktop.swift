import SwiftUI
import AppKit
import Combine

// MARK: - Window

enum MainTab: String { case library, settings }

// MARK: - Sections

// MARK: - Library

struct DesktopView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var clipboard = AppModel.shared.clipboard
    @ObservedObject var notes = AppModel.shared.notes
    @ObservedObject var files = AppModel.shared.files
    @ObservedObject private var nav = MainNav.shared
    @StateObject private var collapsed = Box(Set<String>())
    @StateObject private var editor = NoteEditorController()
    @StateObject private var selecting = Box(false)
    @StateObject private var picked = Box(Set<String>())
    /// The last item clicked while selecting: ⇧-click picks everything from there.
    @StateObject private var anchor = Box<String?>(nil)
    /// On the Pinned page: nil for every pin, "" for pins in no group, or a group's name.
    @StateObject private var pinGroup = Box<String?>(nil)
    /// Zero-based page of the long list on show; goes back to the first page when the list or its filters change.
    @StateObject private var page = Box(0)

    private let grid = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18, alignment: .top)]
    private let cardHeight: CGFloat = 250

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content.background(Look.page)
                .overlay(alignment: .bottom) { ClearConfirmBar(store: clipboard) }
                .overlay(alignment: .bottom) { UndoToast(store: clipboard) }
        }
        .onDisappear { clipboard.releaseFullHistory(MainNav.libraryHolder) }
        .onAppear {
            clipboard.holdFullHistory(MainNav.libraryHolder)
            clipboard.expanded = nil
            // Debug aids for renders: open the Pinned page on one group, or with an app filter on.
            if let g = Env["PIN_GROUP"] { pinGroup.value = g }
            if let app = Env["APP_FILTER"] { clipboard.appFilter = app }
            if Env["SELECT"] != nil {
                selecting.value = true
                picked.value = Set(visibleIDs().prefix(2))
            }
        }
        .onChange(of: nav.section) { _, s in endSelecting(); page.value = 0; if s != .pinned { pinGroup.value = nil } }
        .onChange(of: pinGroup.value) { _, _ in endSelecting(); page.value = 0 }
        .onChange(of: clipboard.filter) { _, _ in page.value = 0 }
        .onChange(of: clipboard.time) { _, _ in page.value = 0 }
        .onChange(of: clipboard.appFilter) { _, _ in page.value = 0 }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarBrand()
            SidebarAction(title: "New Note", symbol: "square.and.pencil") {
                nav.section = .notes; notes.add(); notes.showingList = false
            }
            .padding(.bottom, 4)
            sidebarRow(.all)
            SidebarHeader(title: "Clipboard")
            sidebarRow(.clipboard)
            sidebarRow(.pinned)
            ForEach(clipboard.groups, id: \.self) { name in groupRow(name) }
            SidebarHeader(title: "Saved")
            sidebarRow(.notes)
            sidebarRow(.files)
            Spacer()
            ModeSwitch()
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: Look.sidebarWidth)
        .background(Look.sidebar)
    }

    private func sidebarRow(_ s: DesktopSection) -> some View {
        SidebarRow(title: s.title, symbol: s.symbol, color: s.color, selected: nav.section == s, trailing: count(s).map { "\($0)" })
            .accessibleTap(s.title, selected: nav.section == s) { go(s) }
            .modifier(SidebarDrop(section: s, notes: notes, files: files, clipboard: clipboard, ids: dropIDs))
    }

    /// A group of pins, indented under Pinned: opens the Pinned page showing only that group.
    private func groupRow(_ name: String) -> some View {
        let on = nav.section == .pinned && pinGroup.value == name
        return SidebarRow(title: name, symbol: "square.stack.fill", color: DesktopSection.pinned.color.opacity(0.75), selected: on,
                          trailing: "\(clipboard.clips.filter { $0.pinGroup == name }.count)")
            .padding(.leading, 14)
            .accessibleTap(name, selected: on) { go(.pinned); pinGroup.value = name }
            .modifier(SidebarDrop(section: .pinned, group: name, notes: notes, files: files, clipboard: clipboard, ids: dropIDs))
            .contextMenu {
                Button("Rename Group…") { withAnimation { clipboard.naming = .init(renaming: name) } }
                Button("Delete Group") { if pinGroup.value == name { pinGroup.value = nil }; clipboard.deleteGroup(name) }
            }
    }

    /// What a drop onto a sidebar row moves: every picked item when the dragged one is among them, else just the dragged one.
    private func dropIDs(_ clip: Clip) -> Set<UUID> {
        let picks = Set(picked.value.compactMap(UUID.init(uuidString:)))
        return selecting.value && picks.contains(clip.id) ? picks : [clip.id]
    }

    private func go(_ s: DesktopSection) {
        pinGroup.value = nil
        nav.section = s
        clipboard.expanded = nil
        if s == .notes { notes.showingList = true }
    }

    private func count(_ s: DesktopSection) -> Int? {
        switch s {
        case .all: nil
        case .clipboard: clipboard.totalCount
        case .pinned: clipboard.clips.filter(\.pinned).count
        case .notes: savedNotes.count
        case .files: files.paths.count
        }
    }

    /// Notes with something in them. The store always keeps one blank note ready to type into; the Library does not list it.
    private var savedNotes: [Note] { notes.notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let clip = clipboard.expanded {
            VStack(spacing: 0) {
                HStack { Spacer(); SearchBarButton() }.padding(.horizontal, 32).padding(.top, 58).zIndex(10)
                ExpandedClipView(clip: clip, store: clipboard, inWindow: true)
            }
        } else if nav.section == .notes, !notes.showingList, let id = notes.selectedID {
            noteEditor(id)
        } else if nav.section == .all {
            dashboard
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let scope = filterScope, !selecting.value {
                    FilterHint(scope: scope, clear: showEverything)
                        .padding(.horizontal, 32).padding(.top, 10 - Look.headerGap).padding(.bottom, Look.headerGap - 6)
                }
                if totalItems == 0 {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 0).id("top")
                                cards
                                if pageCount > 1 { PaginationBar(page: pageBinding, pageCount: pageCount, total: totalItems) }
                            }
                            .padding(.horizontal, 32).padding(.bottom, 32).padding(.top, 6)
                        }
                        .onChange(of: currentPage) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            // Right-clicking empty space on a clipboard page acts on the selection, or else on what the filters show.
            .contentShape(Rectangle())
            .contextMenu { if nav.section == .clipboard || nav.section == .pinned { pageMenu } }
            // Files dragged in from Finder go into Quick Access; the other pages do not take drops from Finder.
            .dropDestination(for: URL.self) { urls, _ in
                guard nav.section == .files, !urls.isEmpty else { return false }
                urls.forEach(files.add)
                return true
            }
        }
    }

    /// The shared page header: title with a round "+" where adding makes sense, then this page's filters (clipboard pages) or the
    /// selection bar while selecting, with Select and Search on the right.
    private var header: some View {
        let isClips = nav.section == .clipboard || nav.section == .pinned
        let title = nav.section == .pinned ? (pinGroup.value.map { $0.isEmpty ? "Pinned, No Group" : $0 } ?? "Pinned") : nav.section.title
        return PageHeader(title: title, plus: plusAction, plusLabel: nav.section == .notes ? "New note" : "Add files",
                          onSelect: !selecting.value && !visibleIDs().isEmpty ? { selecting.value = true } : nil) {
            if selecting.value {
                selectionBar
            } else if isClips {
                if nav.section == .pinned { groupFilter }
                TimeMenu(store: clipboard)
                TypeMenu(store: clipboard)
                AppMenu(store: clipboard)
            }
        }
        .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, Look.headerGap)
    }

    /// Which pins the Pinned page shows: all, those in no group, or one group; plus making and tidying groups.
    private var groupFilter: some View {
        let current = pinGroup.value
        return Menu {
            CheckButton("All Pinned", current == nil) { pinGroup.value = nil }
            CheckButton("No Group", current == "") { pinGroup.value = "" }
            if !clipboard.groups.isEmpty { Divider() }
            ForEach(clipboard.groups, id: \.self) { name in CheckButton(name, current == name) { pinGroup.value = name } }
            Divider()
            Button("New Group…") { withAnimation { clipboard.naming = .init() } }
            if let name = current, !name.isEmpty {
                Button("Rename “\(name)”…") { withAnimation { clipboard.naming = .init(renaming: name) } }
                Button("Delete “\(name)”") { pinGroup.value = nil; clipboard.deleteGroup(name) }
            }
        } label: {
            FilterMenuLabel(symbol: "square.stack", value: current.map { $0.isEmpty ? "No group" : $0 } ?? "All groups", active: current != nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
    }

    /// What the Clipboard or Pinned page is narrowed to, in words ("Replies · Images from Ghostty"), or nil when it shows everything.
    private var filterScope: String? {
        guard nav.section == .clipboard || nav.section == .pinned else { return nil }
        let group = nav.section == .pinned ? pinGroup.value.map { $0.isEmpty ? "Pins in no group" : $0 } : nil
        let parts = [group, clipboard.filterSummary].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Clears the time, type and app filters and, on the Pinned page, the group.
    private func showEverything() {
        clipboard.clearFilters()
        pinGroup.value = nil
    }

    private var plusAction: (() -> Void)? {
        switch nav.section {
        case .notes: return { notes.add(); notes.showingList = false }
        case .files: return { addFiles() }
        default: return nil
        }
    }

    @ViewBuilder private var cards: some View {
        switch nav.section {
        case .clipboard: clipboardItems(slice(clips()))
        case .pinned: clipboardItems(slice(pinnedClips()))
        case .notes: notesItems(slice(savedNotes))
        case .files: filesItems(slice(files.paths))
        case .all: EmptyView()
        }
    }

    // MARK: Pages and empty states

    /// How many items the current page has in all, across its pages.
    private var totalItems: Int {
        switch nav.section {
        case .clipboard: clips().count
        case .pinned: pinnedClips().count
        case .notes: savedNotes.count
        case .files: files.paths.count
        case .all: 0
        }
    }
    private var pageCount: Int { max(1, (totalItems + Look.pageSize - 1) / Look.pageSize) }
    private var currentPage: Int { min(page.value, pageCount - 1) }
    private var pageBinding: Binding<Int> { Binding(get: { currentPage }, set: { page.value = $0 }) }
    private func slice<T>(_ items: [T]) -> [T] {
        let start = min(currentPage * Look.pageSize, items.count)
        return Array(items[start..<min(items.count, start + Look.pageSize)])
    }

    /// What each page says when it has nothing to list, with the one action that fills it.
    @ViewBuilder private var emptyState: some View {
        switch nav.section {
        case .clipboard where !clipboard.clips.isEmpty:
            EmptyState(symbol: "line.3.horizontal.decrease.circle", tint: .secondary, title: "No matches",
                       message: "Nothing in your history fits " + (filterScope.map { "“\($0)”." } ?? "these filters."),
                       actionTitle: "Show everything", actionSymbol: "xmark.circle", action: showEverything)
        case .clipboard:
            EmptyState(symbol: "doc.on.clipboard", tint: .blue, title: "Nothing copied yet",
                       message: "Everything you copy lands here, with previews for text, links, pictures and files. Copy something, then click it to paste.",
                       hint: "Scroll down on the menu bar to open Transom from any app.")
        case .pinned where clipboard.clips.contains(where: \.pinned):
            if let g = pinGroup.value, !g.isEmpty, clipboard.filterSummary == nil {
                EmptyState(symbol: "square.stack", tint: .orange, title: "Nothing in \(g) yet",
                           message: "Right-click a clip and choose Move to Group, or drag clips onto “\(g)” in the sidebar.",
                           actionTitle: "Show all pinned", actionSymbol: "pin", action: showEverything)
            } else {
                EmptyState(symbol: "line.3.horizontal.decrease.circle", tint: .secondary, title: "No matches",
                           message: "None of your pinned clips fit " + (filterScope.map { "“\($0)”." } ?? "these filters."),
                           actionTitle: "Show everything", actionSymbol: "xmark.circle", action: showEverything)
            }
        case .pinned where !clipboard.clips.isEmpty:
            EmptyState(symbol: "pin", tint: .orange, title: "Nothing pinned",
                       message: "Pinned clips stay at the top and are never cleared. Right-click a clip and choose Pin, or select several and pin them together.",
                       actionTitle: "Go to Clipboard", actionSymbol: "doc.on.clipboard") { nav.section = .clipboard }
        case .pinned:
            EmptyState(symbol: "pin", tint: .orange, title: "Nothing pinned",
                       message: "Pinned clips stay at the top and are never cleared. Copy something first, then pin it from the Clipboard page.")
        case .notes:
            EmptyState(symbol: "square.and.pencil", tint: .yellow, title: "No notes yet",
                       message: "Jot things down as Markdown. Notes are plain files, so they work in any editor and can live in iCloud Drive.",
                       actionTitle: "New Note", actionSymbol: "plus") { notes.add(); notes.showingList = false }
        case .files:
            EmptyState(symbol: "folder", tint: .blue, title: "Nothing in Quick Access",
                       message: "Keep the files and folders you reach for most one click away. Add them here, or drag them in from Finder.",
                       actionTitle: "Add Files…", actionSymbol: "plus", action: addFiles,
                       hint: "You can also drop files onto this page.")
        case .all:
            EmptyView()
        }
    }

    @ViewBuilder private func clipboardItems(_ list: [Clip]) -> some View {
        if settings.v.clipboardCards {
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list) { c in selectable(c.id.uuidString, clipCard(c)) } }
        } else {
            listBox { ForEach(list) { c in selectable(c.id.uuidString, radius: 8, ClipRow(clip: c, store: clipboard, quickKey: nil, inWindow: true)) } }
        }
    }

    @ViewBuilder private func notesItems(_ list: [Note]) -> some View {
        if settings.v.notesCards {
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list) { n in selectable(n.id.uuidString, noteCard(n)) } }
        } else {
            listBox {
                ForEach(list) { n in
                    selectable(n.id.uuidString, radius: 8, NoteRow(note: n, store: notes, inWindow: true).simultaneousGesture(TapGesture().onEnded { if !selecting.value { nav.section = .notes } }))
                }
            }
        }
    }

    @ViewBuilder private func filesItems(_ list: [String]) -> some View {
        if settings.v.filesCards {
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list, id: \.self) { p in selectable(p, fileCard(p)) } }
        } else {
            listBox { ForEach(list, id: \.self) { p in selectable(p, radius: 8, FileListRow(path: p, store: files)) } }
        }
    }

    private func listBox<C: View>(@ViewBuilder _ rows: () -> C) -> some View {
        LazyVStack(spacing: 2) { rows() }.padding(8).lookCard()
    }

    // MARK: Select and batch actions

    /// Everything the current page shows right now, as selection ids.
    private func visibleIDs() -> [String] {
        switch nav.section {
        case .clipboard: clips().map { $0.id.uuidString }
        case .pinned: pinnedClips().map { $0.id.uuidString }
        case .notes: savedNotes.map { $0.id.uuidString }
        case .files: files.paths
        case .all: []
        }
    }

    private func endSelecting() { selecting.value = false; picked.value = []; anchor.value = nil }

    /// A click while selecting flips one item; ⇧-click picks everything from the last click to this one.
    private func toggle(_ id: String) {
        if NSEvent.modifierFlags.contains(.shift), let a = anchor.value {
            let order = visibleIDs()
            if let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) {
                picked.value.formUnion(order[min(i, j)...max(i, j)])
                return
            }
        }
        if picked.value.contains(id) { picked.value.remove(id) } else { picked.value.insert(id) }
        anchor.value = id
    }

    /// Wraps an item so a click picks it while selecting; nothing changes otherwise.
    @ViewBuilder private func selectable<V: View>(_ id: String, radius: CGFloat = 18, _ view: V) -> some View {
        if selecting.value && nav.section != .all {
            view.overlay { SelectChrome(on: picked.value.contains(id), radius: radius) { toggle(id) } }
        } else {
            view
        }
    }

    /// The bar that replaces the filters while selecting: count on the left, then buttons that all share one shape,
    /// weight and spacing (after Perplexity's and Higgsfield's bulk-action bars). Done is the one filled button.
    private var selectionBar: some View {
        let n = picked.value.count
        let ids = visibleIDs()
        let isClips = nav.section == .clipboard || nav.section == .pinned
        return HStack(spacing: 8) {
            Button { picked.value = [] } label: {
                Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28).background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain).help("Clear selection").accessibilityLabel("Clear selection").opacity(n == 0 ? 0.4 : 1).disabled(n == 0)
            Text(n == 0 ? "Select items" : "\(n) selected").font(.system(size: 13, weight: .medium)).padding(.leading, 2)
            Menu {
                Button("All \(ids.count) items") { picked.value = Set(ids) }.keyboardShortcut("a", modifiers: .command)
                if isClips {
                    Divider()
                    Button("Last 5 minutes") { pickRecent(300) }
                    Button("Last hour") { pickRecent(3600) }
                    Button("Today") { pickRecent(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))) }
                }
                Divider()
                Button("None") { picked.value = [] }
            } label: { SelectBarLabel(title: "Select", symbol: "checklist", chevron: true) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
            Spacer()
            if isClips {
                let allPinned = n > 0 && picked.value.allSatisfy { id in clipboard.clips.first { $0.id.uuidString == id }?.pinned ?? false }
                Button {
                    clipboard.setPinned(!allPinned, ids: Set(picked.value.compactMap(UUID.init(uuidString:))))
                    picked.value = []
                } label: { SelectBarLabel(title: allPinned ? "Unpin" : "Pin", symbol: allPinned ? "pin.slash" : "pin") }
                    .buttonStyle(.plain).disabled(n == 0).opacity(n == 0 ? 0.4 : 1)
                Menu {
                    GroupMenuItems(store: clipboard, ids: Set(picked.value.compactMap(UUID.init(uuidString:)))) { endSelecting() }
                } label: { SelectBarLabel(title: "Group", symbol: "square.stack", chevron: true) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
                    .disabled(n == 0).opacity(n == 0 ? 0.4 : 1)
            }
            Button { deleteSelection() } label: { SelectBarLabel(title: "Delete", symbol: "trash", tint: .red) }
                .buttonStyle(.plain).disabled(n == 0).opacity(n == 0 ? 0.4 : 1)
            Button { endSelecting() } label: { SelectBarLabel(title: "Done", symbol: nil, filled: true) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Look.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Look.hairline, lineWidth: 1))
    }

    /// The right-click menu on empty space of the Clipboard and Pinned pages.
    @ViewBuilder private var pageMenu: some View {
        let ids = Set(picked.value.compactMap(UUID.init(uuidString:)))
        if selecting.value && !ids.isEmpty {
            let allPinned = clipboard.clips.filter { ids.contains($0.id) }.allSatisfy(\.pinned)
            Section("\(ids.count) Selected") {
                Button(allPinned ? "Unpin" : "Pin") { clipboard.setPinned(!allPinned, ids: ids); picked.value = [] }
                Menu("Move to Group") { GroupMenuItems(store: clipboard, ids: ids) { endSelecting() } }
                Button("Copy Together") { clipboard.copyTogether(clipboard.clips.filter { ids.contains($0.id) }) }
                Button("Delete…") { deleteSelection() }
            }
            Button("Done Selecting") { endSelecting() }
        } else {
            ClipboardScopeItems(store: clipboard,
                                selectAll: { selecting.value = true; picked.value = Set(visibleIDs()) },
                                startSelecting: { selecting.value = true }, shown: visibleIDs().count)
        }
    }

    /// Adds the shown clipboard items copied in the last `seconds` to the selection.
    private func pickRecent(_ seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let list = nav.section == .pinned ? pinnedClips() : clips()
        picked.value.formUnion(list.filter { $0.date >= cutoff }.map { $0.id.uuidString })
    }

    private func deleteSelection() {
        let ids = picked.value
        guard !ids.isEmpty else { return }
        let alert = NSAlert()
        let count = ids.count
        let noun: String
        switch nav.section {
        case .notes:
            noun = count == 1 ? "note" : "notes"
            alert.informativeText = "They move to the Trash."
        case .files:
            noun = count == 1 ? "item" : "items"
            alert.informativeText = files.mode == .folder ? "They move to the Trash." : "They are only removed from Quick Access. The files stay where they are."
        default:
            noun = count == 1 ? "clipboard item" : "clipboard items"
            let pinned = clipboard.clips.filter { ids.contains($0.id.uuidString) && $0.pinned }.count
            alert.informativeText = "You can undo this for a few seconds." + (pinned > 0 ? " \(pinned) of them \(pinned == 1 ? "is" : "are") pinned." : "")
        }
        alert.messageText = "Delete \(count) \(noun)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch nav.section {
        case .notes: notes.notes.filter { ids.contains($0.id.uuidString) }.forEach(notes.delete)
        case .files: ids.forEach(files.remove)
        default: clipboard.delete(ids: Set(ids.compactMap(UUID.init(uuidString:))))
        }
        endSelecting()
    }

    // MARK: All: a section per kind of thing

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var dashboard: some View {
        let all = clips()
        let pinned = all.filter(\.pinned)
        let recent = all.filter { !$0.pinned }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: greeting, subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))) { EmptyView() }
                .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, Look.headerGap)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    let plain = pinned.filter { $0.pinGroup == nil }
                    if !plain.isEmpty {
                        section("Pinned", target: .pinned, count: plain.count, seeAll: { go(.pinned); pinGroup.value = "" }) {
                            clipboardItems(Array(plain.prefix(6)))
                        }
                    }
                    ForEach(clipboard.groups, id: \.self) { name in
                        let items = pinned.filter { $0.pinGroup == name }
                        if !items.isEmpty {
                            section(name, key: "group:" + name, symbol: "square.stack.fill", target: .pinned, count: items.count,
                                    seeAll: { go(.pinned); pinGroup.value = name }) {
                                clipboardItems(Array(items.prefix(6)))
                            }
                        }
                    }
                    section("Clipboard", target: .clipboard, count: recent.count) { clipboardItems(Array(recent.prefix(6))) }
                    section("Notes", target: .notes, count: savedNotes.count) { notesItems(Array(savedNotes.prefix(6))) }
                    section("Quick Access", target: .files, count: files.paths.count) { filesItems(Array(files.paths.prefix(6))) }
                }
                .padding(.horizontal, 32).padding(.bottom, 36)
            }
        }
    }

    /// A collapsible section: chevron, title, count, and a link to the full page.
    private func section<C: View>(_ title: String, key: String? = nil, symbol: String? = nil, target: DesktopSection, count: Int,
                                  seeAll: (() -> Void)? = nil, @ViewBuilder cards: () -> C) -> some View {
        let key = key ?? title
        let isOpen = !collapsed.value.contains(key)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90)).frame(width: 14)
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(DesktopSection.pinned.color)
                    }
                    Text(title).font(Look.sectionTitle)
                    Text("\(count)").font(Look.meta).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .accessibleTap("\(title), \(count) items, \(isOpen ? "expanded" : "collapsed")", hint: "Shows or hides the section", combine: false) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if isOpen { collapsed.value.insert(key) } else { collapsed.value.remove(key) }
                    }
                }
                Spacer()
                if count > 0 {
                    Text("See all").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .contentShape(Capsule())
                        .accessibleTap("See all \(title)", combine: false) { if let seeAll { seeAll() } else { go(target) } }
                }
            }
            if isOpen {
                if count == 0 {
                    Text(emptyHint(title)).font(.system(size: 13)).italic().foregroundStyle(.tertiary).padding(.leading, 22)
                } else {
                    cards()
                }
            }
        }
    }

    private func emptyHint(_ title: String) -> String {
        switch title {
        case "Notes": "Press + to start a note"
        case "Quick Access": "Pin files to keep them close"
        default: "Copy something to see it here"
        }
    }

    // MARK: Data

    /// The Pinned page's items: every pin, or one group's.
    private func pinnedClips() -> [Clip] {
        let pins = clips().filter(\.pinned)
        guard let g = pinGroup.value else { return pins }
        return pins.filter { ($0.pinGroup ?? "") == g }
    }

    private func clips() -> [Clip] {
        let list = clipboard.clips.filter {
            $0.category.matches(clipboard.filter) && clipboard.time.includes($0.date)
                && (clipboard.appFilter == nil || ClipboardStore.appKey($0) == clipboard.appFilter)
        }
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    // MARK: Cards

    private func clipCard(_ c: Clip) -> some View {
        LibraryClipCard(clip: c, store: clipboard).frame(height: cardHeight)
    }

    private static let noteColors: [Color] = [
        Color(red: 0.96, green: 0.62, blue: 0.66), Color(red: 0.55, green: 0.78, blue: 0.95), Color(red: 0.95, green: 0.84, blue: 0.40),
        Color(red: 0.60, green: 0.82, blue: 0.64), Color(red: 0.74, green: 0.62, blue: 0.93), Color(red: 0.97, green: 0.72, blue: 0.45),
    ]

    private func noteCard(_ n: Note) -> some View {
        let color = Self.noteColors[abs(n.id.hashValue) % Self.noteColors.count]
        return LibraryCard(frame: color, title: n.title, symbol: "note.text", meta: "Updated \(n.date.formatted(.relative(presentation: .named)))") {
            Text(n.text.split(whereSeparator: \.isNewline).dropFirst().joined(separator: "\n"))
                .font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
        }
        .frame(height: cardHeight)
        .accessibleTap(n.title) { nav.section = .notes; notes.select(n) }
        .onDrag { NSItemProvider(object: n.text as NSString) }
        .contextMenu { NoteMenu(note: n, store: notes) }
    }

    private func fileCard(_ p: String) -> some View {
        let url = URL(fileURLWithPath: p)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        return LibraryCard(frame: Color(red: 0.55, green: 0.70, blue: 0.85), title: url.lastPathComponent, symbol: "doc",
                           meta: [kind, size].compactMap { $0 }.joined(separator: " · ")) {
            Thumb(url: url, size: CGSize(width: 300, height: 150), fill: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.primary.opacity(0.03))
        }
        .frame(height: cardHeight)
        .accessibleTap(url.lastPathComponent, hint: "Opens the file") { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url.lastPathComponent as NSString) }
        .contextMenu { fileMenu(path: p, store: files) }
    }

    // MARK: Notes editor

    private func noteEditor(_ id: UUID) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { notes.showingList = true } label: { Label("All Notes", systemImage: "chevron.left") }.buttonStyle(.borderless)
                Spacer()
                SearchBarButton()
            }
            .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, 12).zIndex(10)
            NoteToolbar(controller: editor).padding(.bottom, 14)
            // The page: a soft card, centred, with the Markdown shown formatted as you type.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                MarkdownEditor(text: notes.binding(for: id), fontSize: settings.v.notesFontSize + 2, controller: editor)
                    .padding(.horizontal, 40).padding(.vertical, 22)
                    .frame(maxWidth: 780, maxHeight: .infinity)
                    .lookCard(radius: 18)
                    .id(id)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = files.mode == .reference ? "Pin" : "Add"
        if panel.runModal() == .OK { panel.urls.forEach(files.add) }
    }
}

// MARK: - Selection

// MARK: - Cards

// MARK: - Library item menu

