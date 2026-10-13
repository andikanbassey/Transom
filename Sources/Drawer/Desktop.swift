import SwiftUI
import AppKit

// MARK: - Window

enum MainTab: String { case library, settings }

final class MainNav: ObservableObject {
    static let shared = MainNav()
    @Published var tab = MainTab.library
    @Published var section = DesktopSection.all
    @Published var paletteOpen = false
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
        case .files: "Search files"
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
            Group {
                if nav.tab == .library { DesktopView() } else { SettingsView() }
            }
        }
        // The open search is drawn here, above a scrim over the whole window, but starting at the header field.
        .overlayPreferenceValue(SearchAnchorKey.self) { anchor in
            GeometryReader { geo in
                if nav.paletteOpen, let anchor {
                    let r = geo[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture { nav.paletteOpen = false }
                        SearchPalette().fixedSize().offset(x: r.maxX - 460, y: r.minY)
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

/// The bottom-left button that flips the window between Library and Settings.
struct SidebarSwitch: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26)
            Text(title).font(.system(size: 14))
            Spacer()
        }
        .foregroundStyle(hovering.value ? Color.primary : Color.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(hovering.value ? Look.selection : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        case .files: "Files"
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

// MARK: - Library

struct DesktopView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var clipboard = AppModel.shared.clipboard
    @ObservedObject var notes = AppModel.shared.notes
    @ObservedObject var files = AppModel.shared.files
    @ObservedObject private var nav = MainNav.shared
    @StateObject private var collapsed = Box(Set<String>())

    private let grid = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18, alignment: .top)]
    private let cardHeight: CGFloat = 250

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Look.hairline).frame(width: 1)
            content.background(Look.page)
        }
        .preferredColorScheme(settings.v.appearance == .system ? nil : (settings.v.appearance == .dark ? .dark : .light))
        .onAppear { clipboard.expanded = nil }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            SidebarBrand()
            ForEach(DesktopSection.allCases, id: \.self) { s in
                SidebarRow(title: s.title, symbol: s.symbol, color: s.color, selected: nav.section == s,
                           trailing: count(s).map { "\($0)" })
                    .onTapGesture { go(s) }
            }
            Spacer()
            SidebarSwitch(title: "Settings", symbol: "gearshape") { MainNav.shared.tab = .settings }
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: Look.sidebarWidth)
        .background(Look.sidebar)
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
            PageHeader(title: nav.section.title, plus: plusAction) { EmptyView() }
            if nav.section == .clipboard || nav.section == .pinned {
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
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list) { clipCard($0) } }
        } else {
            listBox { ForEach(list) { c in ClipRow(clip: c, store: clipboard, quickKey: nil, inWindow: true) } }
        }
    }

    @ViewBuilder private func notesItems(_ list: [Note]) -> some View {
        if settings.v.notesCards {
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list) { noteCard($0) } }
        } else {
            listBox {
                ForEach(list) { n in
                    NoteRow(note: n, store: notes).simultaneousGesture(TapGesture().onEnded { nav.section = .notes })
                }
            }
        }
    }

    @ViewBuilder private func filesItems(_ list: [String]) -> some View {
        if settings.v.filesCards {
            LazyVGrid(columns: grid, spacing: 18) { ForEach(list, id: \.self) { fileCard($0) } }
        } else {
            listBox { ForEach(list, id: \.self) { FileListRow(path: $0, store: files) } }
        }
    }

    private func listBox<C: View>(@ViewBuilder _ rows: () -> C) -> some View {
        LazyVStack(spacing: 2) { rows() }.padding(8).lookCard()
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
                    section("Files", target: .files, count: files.paths.count) { filesItems(Array(files.paths.prefix(6))) }
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
        case "Files": "Pin files to keep them close"
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
        .contextMenu { Button("Delete Note") { notes.delete(n) } }
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
            .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, 8).zIndex(10)
            TextEditor(text: notes.binding(for: id))
                .font(.system(size: settings.v.notesFontSize + 2))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24).padding(.bottom, 16)
                .id(id)
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
            inner
                // Concentric with the frame, so the corners stay true as the stroke shrinks.
                .clipShape(RoundedRectangle(cornerRadius: outerRadius - inset, style: .continuous))
                .padding(inset)
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
        .contextMenu { ClipMenu(clip: clip, store: store) }
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
