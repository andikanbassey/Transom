import SwiftUI
import AppKit

// MARK: - Window

enum MainTab: String { case library, settings }

final class MainNav: ObservableObject {
    static let shared = MainNav()
    @Published var tab = MainTab.library
    @Published var section = DesktopSection.all
    @Published var paletteOpen = false
    /// A search handed in from outside (drawer://search), picked up when the search opens.
    var pendingQuery: String?
    /// The last few things searched for, shown under "Earlier" when the search opens.
    @Published var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    /// What the search looks through: the page you are on decides.
    enum Scope { case all, clipboard, notes, files, settings }
    var scope: Scope {
        if tab == .settings { return .settings }
        switch section {
        case .all: return .all
        case .clipboard, .pinned: return .clipboard
        case .notes: return .notes
        case .files: return .files
        }
    }
    var placeholder: String {
        switch scope {
        case .all: "Search everything"
        case .clipboard: "Search clipboard"
        case .notes: "Search notes"
        case .files: "Search quick access"
        case .settings: "Search settings"
        }
    }

    func remember(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        recents = Array(([q] + recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        UserDefaults.standard.set(recents, forKey: "recentSearches")
    }
}

/// One window for the Library (history, notes, files) and Settings, switched from the sidebar.
/// It sits in the Dock while it is open and goes back to the menu bar when it closes.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(pane: Pane? = nil, tab: MainTab = .settings) {
        if let pane { SettingsNav.shared.pane = pane }
        MainNav.shared.tab = tab
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 620)
            w.contentView = NSHostingView(rootView: MainWindowView())
            w.setFrameAutosaveName("DrawerMainWindow")
            if !w.setFrameUsingName("DrawerMainWindow") { w.center() }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
            window = w
        }
        window?.appearance = Settings.shared.v.appearance.nsAppearance
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainWindowView: View {
    @ObservedObject var nav = MainNav.shared

    var body: some View {
        ZStack(alignment: .top) {
            DesktopView()
        }
        // Settings opens as a sheet over the Library, with the Library still showing behind it.
        .overlay {
            GeometryReader { geo in
                if nav.tab == .settings {
                    ZStack {
                        Color.black.opacity(0.32).contentShape(Rectangle()).onTapGesture { nav.tab = .library }
                        SettingsView()
                            .frame(width: min(940, geo.size.width - 90), height: min(660, geo.size.height - 80))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Look.hairline, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                Button { nav.tab = .library } label: {
                                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26).background(Color.primary.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(16)
                            }
                            .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.16), value: nav.tab)
        // The open search is drawn here, above a scrim over the whole window, but starting at the header field.
        .overlayPreferenceValue(SearchAnchorKey.self) { anchor in
            GeometryReader { geo in
                if nav.paletteOpen, let anchor {
                    let r = geo[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture { nav.paletteOpen = false }
                        SearchPalette().fixedSize().offset(x: r.maxX - SearchPalette.width, y: r.minY)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.14), value: nav.paletteOpen)
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// A plain row at the bottom of the sidebar ("Settings"), with an optional shortcut hint.
struct SidebarAction: View {
    let title: String
    let symbol: String
    var hint: String?
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26)
            Text(title).font(.system(size: 14))
            Spacer()
            if let hint { Text(hint).font(Look.meta).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(hovering.value ? Color.primary : Color.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(hovering.value ? Look.selection.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture(perform: action)
    }
}

// MARK: - Sections

enum DesktopSection: String, CaseIterable {
    case all, clipboard, pinned, notes, files
    var title: String {
        switch self {
        case .all: "All"
        case .clipboard: "Clipboard"
        case .pinned: "Pinned"
        case .notes: "Notes"
        case .files: "Quick Access"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .pinned: "pin.fill"
        case .notes: "note.text"
        case .files: "folder.fill"
        }
    }
    var color: Color {
        switch self {
        case .all: Color(white: 0.45)
        case .clipboard: Color(red: 0.25, green: 0.50, blue: 0.95)
        case .pinned: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .notes: Color(red: 0.95, green: 0.72, blue: 0.18)
        case .files: Color(red: 0.30, green: 0.62, blue: 0.95)
        }
    }
}

/// Dropping a clipboard card on "Notes" or "Quick Access" in the sidebar keeps it there.
struct SidebarDrop: ViewModifier {
    let section: DesktopSection
    let notes: NotesStore
    let files: FilesStore
    @StateObject private var targeted = Box(false)

    func body(content: Content) -> some View {
        if section == .notes || section == .files {
            content
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(targeted.value ? 0.9 : 0), lineWidth: 2))
                .clipDrop(targeted: $targeted.value) { clip in
                    if section == .notes { notes.addClip(clip) } else { files.addClip(clip) }
                }
        } else {
            content
        }
    }
}

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

    private let grid = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18, alignment: .top)]
    private let cardHeight: CGFloat = 250

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Look.hairline).frame(width: 1)
            content.background(Look.page)
        }
        .preferredColorScheme(settings.v.appearance == .system ? nil : (settings.v.appearance == .dark ? .dark : .light))
        .onAppear {
            clipboard.expanded = nil
            if ProcessInfo.processInfo.environment["DRAWER_SELECT"] != nil {
                selecting.value = true
                picked.value = Set(visibleIDs().prefix(2))
            }
        }
        .onChange(of: nav.section) { _, _ in endSelecting() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarBrand()
            SidebarAction(title: "New Note", symbol: "square.and.pencil") {
                nav.section = .notes; notes.add(); notes.showingList = false
            }
            .padding(.bottom, 4)
            sidebarRow(.all)
            SidebarHeader(title: "Clipboard")
            sidebarRow(.clipboard)
            sidebarRow(.pinned)
            SidebarHeader(title: "Saved")
            sidebarRow(.notes)
            sidebarRow(.files)
            Spacer()
            SidebarAction(title: "Settings", symbol: "gearshape", hint: "⌘,") { MainNav.shared.tab = .settings }
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: Look.sidebarWidth)
        .background(Look.sidebar)
    }

    private func sidebarRow(_ s: DesktopSection) -> some View {
        SidebarRow(title: s.title, symbol: s.symbol, color: s.color, selected: nav.section == s, trailing: count(s).map { "\($0)" })
            .onTapGesture { go(s) }
            .modifier(SidebarDrop(section: s, notes: notes, files: files))
    }

    private func go(_ s: DesktopSection) {
        nav.section = s
        clipboard.expanded = nil
        if s == .notes { notes.showingList = true }
    }

    private func count(_ s: DesktopSection) -> Int? {
        switch s {
        case .all: nil
        case .clipboard: clipboard.clips.count
        case .pinned: clipboard.clips.filter(\.pinned).count
        case .notes: notes.notes.count
        case .files: files.paths.count
        }
    }

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
                ScrollView {
                    cards.padding(.horizontal, 32).padding(.bottom, 32).padding(.top, 6)
                }
            }
        }
    }

    /// Title with a round "+" where adding makes sense, and the filter chips on the clipboard page.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: nav.section.title, plus: plusAction) {
                if !selecting.value && !visibleIDs().isEmpty {
                    Button { selecting.value = true } label: { Label("Select", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            if selecting.value {
                selectionBar
            } else if nav.section == .clipboard || nav.section == .pinned {
                HStack(spacing: 8) {
                    FilterPills(store: clipboard, window: true)
                    TimeChip(store: clipboard)
                }
            }
        }
        .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, 14)
        .zIndex(10)
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
        case .clipboard: clipboardItems(clips())
        case .pinned: clipboardItems(clips().filter(\.pinned))
        case .notes: notesItems(notes.notes)
        case .files: filesItems(files.paths)
        case .all: EmptyView()
        }
    }

    // MARK: Cards or lists, per kind (Settings › Appearance › Items)

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
        case .pinned: clips().filter(\.pinned).map { $0.id.uuidString }
        case .notes: notes.notes.map { $0.id.uuidString }
        case .files: files.paths
        case .all: []
        }
    }

    private func endSelecting() { selecting.value = false; picked.value = [] }

    private func toggle(_ id: String) {
        if picked.value.contains(id) { picked.value.remove(id) } else { picked.value.insert(id) }
    }

    /// Wraps an item so a click picks it while selecting; nothing changes otherwise.
    @ViewBuilder private func selectable<V: View>(_ id: String, radius: CGFloat = 18, _ view: V) -> some View {
        if selecting.value && nav.section != .all {
            let on = picked.value.contains(id)
            view
                .overlay {
                    Color.clear.contentShape(Rectangle()).onTapGesture { toggle(id) }
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5).allowsHitTesting(false))
                        .background(on ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .overlay(alignment: .topLeading) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.7), .white)
                        .background(Circle().fill(.white.opacity(on ? 1 : 0.6)).padding(2))
                        .offset(x: -7, y: -7).allowsHitTesting(false)
                }
        } else {
            view
        }
    }

    private var selectionBar: some View {
        let n = picked.value.count
        let ids = visibleIDs()
        return HStack(spacing: 10) {
            Text(n == 0 ? "Select items" : "\(n) selected").font(.system(size: 13, weight: .semibold)).frame(minWidth: 84, alignment: .leading)
            Menu {
                Button("All \(ids.count) shown") { picked.value = Set(ids) }.keyboardShortcut("a", modifiers: .command)
                if nav.section == .clipboard || nav.section == .pinned {
                    Divider()
                    Button("Last 5 minutes") { pickRecent(300) }
                    Button("Last hour") { pickRecent(3600) }
                    Button("Today") { pickRecent(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))) }
                }
                Divider()
                Button("None") { picked.value = [] }
            } label: { Label("Select", systemImage: "checklist") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            if (nav.section == .clipboard || nav.section == .pinned), n > 0 {
                let allPinned = picked.value.allSatisfy { id in clipboard.clips.first { $0.id.uuidString == id }?.pinned ?? false }
                Button(allPinned ? "Unpin" : "Pin") {
                    clipboard.setPinned(!allPinned, ids: Set(picked.value.compactMap(UUID.init(uuidString:))))
                    picked.value = []
                }.buttonStyle(.borderless)
            }
            Button(role: .destructive) { deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(.borderless).foregroundStyle(n == 0 ? Color.secondary : Color.red).disabled(n == 0)
            Button("Done") { endSelecting() }.keyboardShortcut(.cancelAction).buttonStyle(.borderless).fontWeight(.semibold)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Adds the shown clipboard items copied in the last `seconds` to the selection.
    private func pickRecent(_ seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let list = nav.section == .pinned ? clips().filter(\.pinned) : clips()
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
            alert.informativeText = "This can't be undone." + (pinned > 0 ? " \(pinned) of them \(pinned == 1 ? "is" : "are") pinned." : "")
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
                .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !pinned.isEmpty {
                        section("Pinned", target: .pinned, count: pinned.count) { clipboardItems(Array(pinned.prefix(6))) }
                    }
                    section("Clipboard", target: .clipboard, count: recent.count) { clipboardItems(Array(recent.prefix(6))) }
                    section("Notes", target: .notes, count: notes.notes.count) { notesItems(Array(notes.notes.prefix(6))) }
                    section("Quick Access", target: .files, count: files.paths.count) { filesItems(Array(files.paths.prefix(6))) }
                }
                .padding(.horizontal, 32).padding(.bottom, 36)
            }
        }
    }

    /// A collapsible section: chevron, title, count, and a link to the full page.
    private func section<C: View>(_ title: String, target: DesktopSection, count: Int, @ViewBuilder cards: () -> C) -> some View {
        let isOpen = !collapsed.value.contains(title)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90)).frame(width: 14)
                    Text(title).font(Look.sectionTitle)
                    Text("\(count)").font(Look.meta).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if isOpen { collapsed.value.insert(title) } else { collapsed.value.remove(title) }
                    }
                }
                Spacer()
                if count > 0 {
                    Text("See all").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { go(target) }
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

    private func clips() -> [Clip] {
        let list = clipboard.clips.filter { $0.category.matches(clipboard.filter) && clipboard.time.includes($0.date) }
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
        .onTapGesture { nav.section = .notes; notes.select(n) }
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
        .onTapGesture { NSWorkspace.shared.open(url) }
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

// MARK: - Cards

/// A Craft-style card: a coloured frame that fades toward the bottom, around a soft white card. On hover the white
/// card grows outward over the frame until the stroke is gone; it settles back when the pointer leaves.
struct LibraryCard<Preview: View>: View {
    let frame: Color
    let title: String
    let symbol: String
    let meta: String
    var appIcon: NSImage?
    var tint: Color?
    @ViewBuilder var preview: () -> Preview
    @StateObject private var hovering = Box(false)
    private let outerRadius: CGFloat = 18
    private let stroke: CGFloat = 5

    var body: some View {
        let inset = hovering.value ? 0 : stroke
        ZStack {
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(LinearGradient(colors: [frame.opacity(0.9), frame.opacity(0.5), frame.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            // The content is laid out once, at the card's full size, and only the clip shape changes with hover.
            // Nothing inside reflows or moves, so the text stays still while the card grows over the stroke.
            inner
                .mask(
                    RoundedRectangle(cornerRadius: outerRadius - inset, style: .continuous)
                        .padding(inset)
                )
        }
        .shadow(color: .black.opacity(hovering.value ? 0.13 : 0.07), radius: hovering.value ? 12 : 8, y: hovering.value ? 5 : 3)
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .animation(.easeInOut(duration: 0.28), value: hovering.value)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint ?? frame)
                        Text(meta).font(Look.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 6)
                if let appIcon {
                    Image(nsImage: appIcon).resizable().aspectRatio(contentMode: .fit).frame(width: 38, height: 38)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            Rectangle().fill(Look.hairline).frame(height: 1).padding(.horizontal, 14)
            preview().clipped()
        }
        .background(Look.card)
    }
}

/// A clipboard item in the Library: click copies it, drag takes it into another app.
struct LibraryClipCard: View {
    let clip: Clip
    let store: ClipboardStore
    @StateObject private var copied = Box(false)

    var body: some View {
        let cat = clip.category
        LibraryCard(frame: cat.tint, title: clip.title, symbol: cat.symbol,
                    meta: "\(cat.label) · \(clip.date.formatted(.relative(presentation: .named)))",
                    appIcon: AppIcons.icon(clip.sourceBundleID), tint: cat.tint) {
            ClipPreview(clip: clip).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if copied.value {
                Text("Copied").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(.black.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if clip.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(cat.tint, in: Circle()).offset(x: 4, y: -4)
            }
        }
        .onTapGesture {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip; return }
            store.copy(clip)
            if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
            withAnimation(.easeOut(duration: 0.15)) { copied.value = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { copied.value = false } }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { LibraryClipMenu(clip: clip, store: store) }
    }
}

/// "Any time", "Last hour", "Today"…: a chip with a menu, next to the type chips.
struct TimeChip: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        Menu {
            ForEach(TimeFilter.allCases, id: \.self) { t in
                Button { store.time = t } label: {
                    if store.time == t { Label(t.rawValue, systemImage: "checkmark") } else { Text(t.rawValue) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 12, weight: .medium))
                Text(store.time.rawValue).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(store.time == .any ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(store.time == .any ? Color.primary.opacity(0.055) : Color.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

// MARK: - Library item menu

/// Right-click menu for a clipboard item in the Library: only things you can do with the item itself.
struct LibraryClipMenu: View {
    let clip: Clip
    let store: ClipboardStore

    var body: some View {
        let cat = clip.category
        let file = clip.imageURL ?? clip.fileURLs.first
        // Grouped the way Craft groups its menus: use it, open it, send it somewhere, then pin and delete last.
        Button {
            store.copy(clip)
            if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
        } label: { Label(cat == .image || cat == .gif ? "Copy Image" : "Copy", systemImage: "doc.on.doc") }
        Button { store.expanded = clip } label: { Label("Open in Full", systemImage: "arrow.up.left.and.arrow.down.right") }
        Divider()
        switch cat {
        case .image, .gif:
            if let url = file {
                Button { Self.open(url, withBundleID: "com.apple.Preview") } label: { Label("Open in Preview", systemImage: "eye") }
                Button { Self.save(url) } label: { Label("Save Image As…", systemImage: "square.and.arrow.down") }
            }
        case .video, .audio:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label(cat == .video ? "Play" : "Play Audio", systemImage: "play") } }
        case .pdf:
            if let url = file { Button { Self.open(url, withBundleID: "com.apple.Preview") } label: { Label("Open in Preview", systemImage: "eye") } }
        case .folder:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label("Open Folder", systemImage: "folder") } }
        case .file:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") } }
        case .link:
            if let t = clip.text?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: t) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open Link", systemImage: "safari") }
            }
        case .text, .color:
            EmptyView()
        }
        if let url = clip.fileURLs.first ?? clip.imageURL {
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
        }
        Menu {
            Button { AppModel.shared.notes.addClip(clip) } label: { Label("Notes", systemImage: "note.text") }
            Button { AppModel.shared.files.addClip(clip) } label: { Label("Quick Access", systemImage: "folder") }
        } label: { Label("Save To", systemImage: "tray.and.arrow.down") }
        if let url = clip.imageURL ?? clip.fileURLs.first {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        } else if let text = clip.text, !text.isEmpty {
            ShareLink(item: text) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button { store.togglePin(clip) } label: { Label(clip.pinned ? "Unpin" : "Pin", systemImage: clip.pinned ? "pin.slash" : "pin") }
        Divider()
        Button(role: .destructive) { store.delete(clip) } label: { Label("Delete", systemImage: "trash") }
    }

    private static func open(_ url: URL, withBundleID id: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { NSWorkspace.shared.open(url); return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }
}
