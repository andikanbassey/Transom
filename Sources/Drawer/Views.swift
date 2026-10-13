import SwiftUI
import AppKit

/// Stand-in for @State: the Command Line Tools SDK lacks the SwiftUI macro plugin that @State needs.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Drawer

struct DrawerView: View {
    @ObservedObject var layout = AppModel.shared.layout
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let v = settings.v
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
        let tint = Color(nsColor: .windowBackgroundColor).opacity(v.translucency)
        // The global settings gear lives on the right-most visible panel.
        let last: Panel? = v.showNotes ? .notes : (v.showFiles ? .files : (v.showClipboard ? .clipboard : nil))
        HStack(spacing: 0) {
            if v.showClipboard { ClipboardColumn(store: AppModel.shared.clipboard, showsGear: last == .clipboard).frame(maxWidth: .infinity) }
            if v.showClipboard && (v.showFiles || v.showNotes) { divider }
            if v.showFiles { FilesColumn(store: AppModel.shared.files, showsGear: last == .files).frame(maxWidth: .infinity) }
            if v.showFiles && v.showNotes { divider }
            if v.showNotes { NotesColumn(store: AppModel.shared.notes, showsGear: last == .notes).frame(maxWidth: .infinity) }
            if last == nil {
                Text("All panels are hidden. Right-click here to bring some back.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .padding(.top, layout.topInset)
        .contentShape(Rectangle())
        .contextMenu { AppMenuItems() }
        .glassSurface(shape, tint: tint, enabled: v.liquidGlass)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 14)
    }
}

enum Panel { case clipboard, files, notes }

/// Menu for right-clicking anywhere on the drawer that is not a row of its own.
struct AppMenuItems: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Button(settings.v.paused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") { settings.v.paused.toggle() }
        Divider()
        Menu("Panels") {
            CheckButton("Clipboard", settings.v.showClipboard) { settings.v.showClipboard.toggle() }
            CheckButton("Files", settings.v.showFiles) { settings.v.showFiles.toggle() }
            CheckButton("Notes", settings.v.showNotes) { settings.v.showNotes.toggle() }
        }
        Divider()
        Button("Settings…") { AppModel.shared.openSettings(nil) }
        Button("Clipboard Settings…") { AppModel.shared.openSettings(.clipboard) }
        Button("Files Settings…") { AppModel.shared.openSettings(.files) }
        Button("Notes Settings…") { AppModel.shared.openSettings(.notes) }
        Divider()
        Button("Close Drawer") { AppModel.shared.hideDrawer() }
    }
}

/// A menu item with a checkmark when selected.
struct CheckButton: View {
    let title: String
    let checked: Bool
    let action: () -> Void
    init(_ title: String, _ checked: Bool, action: @escaping () -> Void) { self.title = title; self.checked = checked; self.action = action }
    var body: some View {
        Button(action: action) {
            if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

// MARK: - Shared pieces

struct HeaderIcon: View {
    let symbol: String
    var active = false
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? Color.accentColor : (hovering.value ? Color.primary : Color.secondary))
            .frame(width: 26, height: 26)
            .background(hovering.value ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering.value = $0 }
            .onTapGesture(perform: action)
    }
}

/// The "⋯" button each panel has for its own options.
struct PanelMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Menu { content() } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26, height: 26)
        .help("Panel options")
    }
}

struct ColumnHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        ZStack {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary.opacity(0.7))
            HStack(spacing: 2) { Spacer(); trailing() }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}

struct Pill: View {
    let category: Category
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.system(size: 9, weight: .semibold))
            Text(category.label).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(category.tint)
        .background(category.tint.opacity(0.16), in: Capsule())
    }
}

/// Cover art loaded from QuickLook.
struct Thumb: View {
    let url: URL
    let size: CGSize
    var fill = true
    @StateObject private var img = Box<NSImage?>(nil)

    var body: some View {
        Group {
            if let i = img.value {
                if fill { Image(nsImage: i).resizable().scaledToFill() } else { Image(nsImage: i).resizable().scaledToFit() }
            } else {
                Color.primary.opacity(0.05)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: url) { img.value = await Thumbs.image(for: url, size: size) ?? NSWorkspace.shared.icon(forFile: url.path) }
    }
}

/// Quiet heading that groups clipboard rows by how recently they were copied.
struct GroupHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
    }
}

// MARK: - Clipboard

/// How recently an item was copied. Pinned items sit above everything else.
enum TimeGroup: CaseIterable {
    case pinned, hour, today, yesterday, week, month, older

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .hour: "Past Hour"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "This Week"
        case .month: "This Month"
        case .older: "Older"
        }
    }

    static func of(_ clip: Clip, now: Date = Date()) -> TimeGroup {
        if clip.pinned { return .pinned }
        let age = now.timeIntervalSince(clip.date)
        let cal = Calendar.current
        if age < 3600 { return .hour }
        if cal.isDateInToday(clip.date) { return .today }
        if cal.isDateInYesterday(clip.date) { return .yesterday }
        if age < 7 * 86_400 { return .week }
        if age < 30 * 86_400 { return .month }
        return .older
    }
}

struct ClipboardColumn: View {
    @ObservedObject var store: ClipboardStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let visible = store.visible
        let now = Date()
        let index = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1.id, $0) })
        let groups = TimeGroup.allCases.compactMap { g -> (TimeGroup, [Clip])? in
            let items = visible.filter { TimeGroup.of($0, now: now) == g }
            return items.isEmpty ? nil : (g, items)
        }
        VStack(spacing: 0) {
            ColumnHeader(title: "Clipboard History") {
                HeaderIcon(symbol: settings.v.paused ? "pause.circle.fill" : "record.circle", active: settings.v.paused) {
                    settings.v.paused.toggle()
                }
                .help(settings.v.paused ? "Clipboard capture paused" : "Pause clipboard capture")
                Menu {
                    ForEach(Category.Filter.allCases, id: \.self) { f in
                        CheckButton(f.rawValue, store.filter == f) { store.filter = f }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.filter == .all ? Color.secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26, height: 26)
                HeaderIcon(symbol: store.pinnedOnly ? "star.fill" : "star", active: store.pinnedOnly) { store.pinnedOnly.toggle() }
                HeaderIcon(symbol: "magnifyingglass", active: store.searching) {
                    store.searching.toggle()
                    if !store.searching { store.query = "" }
                }
                PanelMenu {
                    Button(settings.v.paused ? "Resume Capture" : "Pause Capture") { settings.v.paused.toggle() }
                    Button("Clear Unpinned Items") { store.clearUnpinned() }
                    Divider()
                    Button("Clipboard Settings…") { AppModel.shared.openSettings(.clipboard) }
                    Button("Hide Clipboard Panel") { settings.v.showClipboard = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.searching {
                TextField("Search clipboard", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            if visible.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text(store.clips.isEmpty ? "Copy something to see it here" : "No matches")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(groups, id: \.0) { group, items in
                            GroupHeader(title: group.title)
                            ForEach(items) { clip in
                                let n = index[clip.id] ?? 99
                                ClipRow(clip: clip, store: store, quickKey: settings.v.quickPaste && n < 9 ? n + 1 : nil)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
            }
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let store: ClipboardStore
    var quickKey: Int?
    @StateObject private var hovering = Box(false)
    private let cover: CGFloat = 54

    var body: some View {
        let cat = clip.category
        HStack(spacing: 10) {
            Image(systemName: clip.pinned ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundStyle(clip.pinned ? Color.yellow : Color.secondary.opacity(hovering.value ? 0.8 : 0))
                .frame(width: 14)
                .contentShape(Rectangle())
                .onTapGesture { store.togglePin(clip) }
            coverArt(cat)
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(cat == .text ? 2 : 1).truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                Pill(category: cat)
            }
            Spacer(minLength: 4)
            ZStack {
                if hovering.value {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .onTapGesture { store.delete(clip) }
                } else {
                    HStack(spacing: 6) {
                        if let icon = AppIcons.icon(clip.sourceBundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18).opacity(0.85)
                        }
                        if let n = quickKey {
                            Text("\(Settings.shared.v.quickPasteModifier.symbol)\(n)")
                                .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(hovering.value ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture { AppModel.shared.use(clip) }
        .contextMenu {
            Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip) }
            if let first = clip.fileURLs.first {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first]) }
            }
            if let id = clip.sourceBundleID, let name = clip.sourceApp {
                Button("Never Record from \(name)") {
                    Settings.shared.block(AppRef(bundleID: id, name: name))
                    Settings.shared.v.captureMode = .blockList
                }
            }
            Button("Delete") { store.delete(clip) }
            Divider()
            AppMenuItems()
        }
    }

    /// A square cover that says what the clip is: real artwork for media, a tinted symbol for the rest.
    @ViewBuilder private func coverArt(_ cat: Category) -> some View {
        let size = CGSize(width: cover, height: cover)
        switch cat {
        case .color:
            (Clip.hexColor((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .gray)
        case .image, .gif, .video:
            ZStack {
                if let url = clip.previewURL { Thumb(url: url, size: size) }
                if cat == .video {
                    Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle())
                }
            }
        case .pdf, .folder, .file:
            ZStack {
                Color.primary.opacity(0.06)
                if let url = clip.previewURL { Thumb(url: url, size: CGSize(width: cover - 8, height: cover - 8), fill: false) }
            }
        case .link where clip.linkImageURL != nil:
            Thumb(url: clip.linkImageURL!, size: size)
        case .text, .link, .audio:
            ZStack {
                cat.tint.opacity(0.18)
                Image(systemName: cat == .text ? "text.alignleft" : cat.symbol)
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(cat.tint)
            }
        }
    }
}

// MARK: - Files

struct FilesColumn: View {
    @ObservedObject var store: FilesStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var targeted = Box(false)

    private var gridMin: CGFloat {
        switch settings.v.filesIconSize { case .small: 64; case .medium: 84; case .large: 112 }
    }
    private var iconSize: CGFloat {
        switch settings.v.filesIconSize { case .small: 34; case .medium: 44; case .large: 62 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Files") {
                HeaderIcon(symbol: "plus", action: addFiles).help(store.mode == .reference ? "Pin files or folders" : "Add files to the folder")
                PanelMenu {
                    if store.mode == .folder {
                        Button("Show in Finder") { NSWorkspace.shared.open(FilesStore.folder) }
                        Divider()
                    }
                    Menu("Arrange By") {
                        ForEach(FileSort.allCases, id: \.self) { s in CheckButton(s.label, settings.v.filesSort == s) { settings.v.filesSort = s } }
                    }
                    CheckButton("Keep Folders on Top", settings.v.filesFoldersOnTop) { settings.v.filesFoldersOnTop.toggle() }
                    Menu("View As") {
                        ForEach(FilesView.allCases, id: \.self) { f in CheckButton(f.label, settings.v.filesView == f) { settings.v.filesView = f } }
                    }
                    Menu("Item Size") {
                        ForEach(FileIconSize.allCases, id: \.self) { z in CheckButton(z.label, settings.v.filesIconSize == z) { settings.v.filesIconSize = z } }
                    }
                    Divider()
                    Button("Files Settings…") { AppModel.shared.openSettings(.files) }
                    Button("Hide Files Panel") { settings.v.showFiles = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.paths.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "pin").font(.system(size: 20)).foregroundStyle(.tertiary)
                    Text(store.mode == .reference ? "Drop files here or press + to pin them" : "Drop files here to keep a copy")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                Spacer()
            } else if settings.v.filesView == .list {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.paths, id: \.self) { path in FileListRow(path: path, store: store) }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: gridMin), spacing: 6)], spacing: 8) {
                        ForEach(store.paths, id: \.self) { path in FileTile(path: path, store: store, iconSize: iconSize) }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(targeted.value ? 0.8 : 0), lineWidth: 2).padding(6))
        .onDrop(of: [.fileURL], isTargeted: $targeted.value) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { store.add(url) }
                }
            }
            return true
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = store.mode == .reference ? "Pin" : "Add"
        // The drawer is a floating panel: lift the dialog above it.
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach(store.add) }
    }
}

private func fileMenu(path: String, store: FilesStore) -> some View {
    let url = URL(fileURLWithPath: path)
    return Group {
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button(store.mode == .reference ? "Unpin" : "Move to Trash") { store.remove(path) }
        Divider()
        AppMenuItems()
    }
}

struct FileTile: View {
    let path: String
    let store: FilesStore
    let iconSize: CGFloat
    @StateObject private var hovering = Box(false)

    var body: some View {
        let url = URL(fileURLWithPath: path)
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: iconSize, height: iconSize)
            Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(hovering.value ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.4)
        .onHover { hovering.value = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { fileMenu(path: path, store: store) }
    }
}

struct FileListRow: View {
    let path: String
    let store: FilesStore
    @StateObject private var hovering = Box(false)

    var body: some View {
        let url = URL(fileURLWithPath: path)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
            Text(url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering.value ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.4)
        .onHover { hovering.value = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { fileMenu(path: path, store: store) }
    }
}

// MARK: - Notes

struct NotesColumn: View {
    @ObservedObject var store: NotesStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var query = Box("")

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Notes") {
                HeaderIcon(symbol: "plus") { store.add() }.help("New note")
                HeaderIcon(symbol: "list.bullet", active: store.showingList) { store.showingList.toggle() }.help("All notes")
                PanelMenu {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.folder) }
                    Divider()
                    Button("Notes Settings…") { AppModel.shared.openSettings(.notes) }
                    Button("Hide Notes Panel") { settings.v.showNotes = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.showingList { list } else { editor }
        }
    }

    @ViewBuilder private var editor: some View {
        if let id = store.selectedID {
            ZStack(alignment: .topLeading) {
                if store.notes.first(where: { $0.id == id })?.text.isEmpty ?? true {
                    Text("Quick notes, phone numbers, tasks…")
                        .font(.system(size: settings.v.notesFontSize)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 19).padding(.top, 8)
                }
                TextEditor(text: store.binding(for: id))
                    .font(.system(size: settings.v.notesFontSize))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14).padding(.bottom, 10)
                    .id(id)
            }
        }
    }

    private var list: some View {
        let q = query.value.trimmingCharacters(in: .whitespaces)
        let shown = store.notes.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) }
        return VStack(spacing: 6) {
            TextField("Search notes", text: $query.value)
                .textFieldStyle(.plain).font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown) { note in NoteRow(note: note, store: store) }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let store: NotesStore
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text(note.preview.isEmpty ? note.date.formatted(date: .abbreviated, time: .omitted) : note.preview)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if hovering.value {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .onTapGesture { store.delete(note) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hovering.value || note.id == store.selectedID ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture { store.select(note) }
        .contextMenu {
            Button("Show in Finder") {
                if let f = note.fileName { NSWorkspace.shared.activateFileViewerSelecting([store.folder.appendingPathComponent(f)]) }
            }
            Button("Delete") { store.delete(note) }
            Divider()
            AppMenuItems()
        }
    }
}
