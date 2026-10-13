import AppKit
import SwiftUI
import Combine

let supportDir: URL = {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Drawer", isDirectory: true)
    try? FileManager.default.createDirectory(at: url.appendingPathComponent("images"), withIntermediateDirectories: true)
    return url
}()

// MARK: - Files

/// Pinned files either reference files where they are, or live as copies in a folder
/// (which can be inside iCloud Drive).
final class FilesStore: ObservableObject {
    @Published var paths: [String] = []
    private let refFile = supportDir.appendingPathComponent("files.json")
    private var refs: [String] = []
    private var signature = ""
    private var cancellable: AnyCancellable?

    var mode: FilesMode { Settings.shared.v.filesMode }
    static var folder: URL {
        Settings.shared.v.filesFolder.map { URL(fileURLWithPath: $0) } ?? supportDir.appendingPathComponent("Files")
    }

    init() {
        if let data = try? Data(contentsOf: refFile), let saved = try? JSONDecoder().decode([String].self, from: data) { refs = saved }
        reload()
        signature = currentSignature
        cancellable = Settings.shared.$v.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let sig = self.currentSignature
                if sig != self.signature { self.signature = sig; self.reload() }
            }
        }
    }

    private var currentSignature: String {
        let v = Settings.shared.v
        return "\(mode)|\(Self.folder.path)|\(v.filesSort)|\(v.filesFoldersOnTop)"
    }

    func reload() {
        let list: [String]
        switch mode {
        case .reference:
            list = refs
        case .folder:
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            list = ((try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).map(\.path)
        }
        let sorted = sort(list)
        if paths != sorted { paths = sorted }
    }

    /// Orders files by the "Arrange By" choice, optionally keeping folders first.
    private func sort(_ list: [String]) -> [String] {
        let v = Settings.shared.v
        struct Info { var path: String; var name: String; var kind: String; var modified: Date; var added: Date; var isDir: Bool }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .addedToDirectoryDateKey, .creationDateKey,
                                         .localizedTypeDescriptionKey, .isDirectoryKey]
        let infos: [Info] = list.enumerated().map { index, path in
            let url = URL(fileURLWithPath: path)
            let r = try? url.resourceValues(forKeys: keys)
            // A pinned reference has no date of its own, so "added" is the order it was pinned in.
            let added = mode == .reference ? Date(timeIntervalSince1970: Double(refs.firstIndex(of: path) ?? index))
                                           : (r?.addedToDirectoryDate ?? r?.creationDate ?? .distantPast)
            return Info(path: path, name: url.lastPathComponent, kind: r?.localizedTypeDescription ?? "",
                        modified: r?.contentModificationDate ?? .distantPast, added: added, isDir: r?.isDirectory ?? false)
        }
        var out = infos.sorted { a, b in
            switch v.filesSort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .kind: return a.kind == b.kind ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.kind < b.kind
            case .dateAdded: return a.added > b.added
            case .dateModified: return a.modified > b.modified
            }
        }
        if v.filesFoldersOnTop { out = out.filter(\.isDir) + out.filter { !$0.isDir } }
        return out.map(\.path)
    }

    func add(_ url: URL) {
        switch mode {
        case .reference:
            guard !refs.contains(url.path) else { return }
            refs.append(url.path)
            saveRefs()
        case .folder:
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            if url.deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL { return }
            var dest = Self.folder.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
                dest = Self.folder.appendingPathComponent("\(base) \(n)\(ext)")
                n += 1
            }
            try? fm.copyItem(at: url, to: dest)
        }
        reload()
    }

    /// "New Folder" in the Files options: only meaningful when files live in a folder.
    func newFolder() {
        guard mode == .folder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var dest = Self.folder.appendingPathComponent("untitled folder")
        var n = 2
        while fm.fileExists(atPath: dest.path) { dest = Self.folder.appendingPathComponent("untitled folder \(n)"); n += 1 }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        reload()
    }

    /// Files copied in Finder are pinned (or copied into the folder) from the clipboard.
    func pasteFromClipboard() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        urls.forEach(add)
    }

    func remove(_ path: String) {
        switch mode {
        case .reference:
            refs.removeAll { $0 == path }
            saveRefs()
        case .folder:
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        }
        reload()
    }

    private func saveRefs() {
        if let data = try? JSONEncoder().encode(refs) { try? data.write(to: refFile, options: .atomic) }
    }
}

// MARK: - Notes

struct Note: Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var date = Date()
    var fileName: String?

    /// First non-empty line, shown in the notes list.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "New note" : line
    }

    /// The next non-empty line after the title, shown under it in the list.
    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.count > 1 ? lines[1] : ""
    }
}

/// Notes are plain Markdown files in a folder, so they can live in iCloud Drive or any synced folder.
final class NotesStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?
    /// The notes list is the front page; the last view is remembered between launches.
    @Published var showingList = true { didSet { Settings.shared.v.notesShowingList = showingList } }
    private var dirty = Set<UUID>()
    private var pending: DispatchWorkItem?
    private var folderPath = ""
    private var cancellable: AnyCancellable?

    private struct LegacyNote: Codable { var text: String; var date: Date }

    var folder: URL {
        Settings.shared.v.notesFolder.map { URL(fileURLWithPath: $0) } ?? supportDir.appendingPathComponent("Notes")
    }

    init() {
        migrateLegacy()
        folderPath = folder.path
        loadFromDisk()
        restoreView()
        cancellable = Settings.shared.$v.sink { [weak self] _ in
            DispatchQueue.main.async { self?.folderMaybeChanged() }
        }
    }

    var selectedIndex: Int? { notes.firstIndex { $0.id == selectedID } }

    private func restoreView() {
        let v = Settings.shared.v
        if let f = v.lastNoteFile, let n = notes.first(where: { $0.fileName == f }) { selectedID = n.id }
        showingList = v.notesOpenWith == .list ? true : v.notesShowingList
    }

    /// Called each time the drawer opens.
    func drawerOpened() {
        if Settings.shared.v.notesOpenWith == .list { showingList = true }
    }

    private func rememberSelection() {
        Settings.shared.v.lastNoteFile = notes.first { $0.id == selectedID }?.fileName
    }

    // MARK: Disk

    private func loadFromDisk() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var loaded: [Note] = []
        for u in urls where ["md", "txt"].contains(u.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let id = notes.first { $0.fileName == u.lastPathComponent }?.id ?? UUID()
            loaded.append(Note(id: id, text: text, date: date, fileName: u.lastPathComponent))
        }
        loaded.sort { $0.date > $1.date }
        if loaded.isEmpty {
            // Keep an untouched blank note as it is, so the editor does not flicker.
            if notes.count == 1, notes[0].text.isEmpty { return }
            loaded = [Note()]
        }
        if loaded != notes { notes = loaded }
        if selectedIndex == nil { selectedID = notes.first?.id }
        dirty = []
    }

    /// Pick up edits made outside the app (Finder, another Mac through iCloud).
    func refreshIfClean() {
        if dirty.isEmpty { loadFromDisk() }
    }

    private func folderMaybeChanged() {
        guard folder.path != folderPath else { return }
        folderPath = folder.path
        let old = notes.filter { !$0.text.isEmpty }
        loadFromDisk()
        // First time in a new folder: bring the existing notes along.
        if notes.allSatisfy({ $0.text.isEmpty }), !old.isEmpty {
            notes = old.map { var n = $0; n.fileName = nil; return n }
            dirty = Set(notes.map(\.id))
            selectedID = notes.first?.id
            flush()
        }
    }

    private func migrateLegacy() {
        let fm = FileManager.default
        let json = supportDir.appendingPathComponent("notes.json")
        let txt = supportDir.appendingPathComponent("notes.txt")
        var legacy: [LegacyNote] = []
        if let data = try? Data(contentsOf: json), let saved = try? JSONDecoder().decode([LegacyNote].self, from: data) {
            legacy = saved
        } else if let text = try? String(contentsOf: txt, encoding: .utf8), !text.isEmpty {
            legacy = [LegacyNote(text: text, date: Date())]
        }
        legacy = legacy.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !legacy.isEmpty else { return }
        notes = legacy.map { Note(text: $0.text, date: $0.date) }
        dirty = Set(notes.map(\.id))
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        flush()
        try? fm.moveItem(at: json, to: supportDir.appendingPathComponent("notes.json.migrated"))
        try? fm.moveItem(at: txt, to: supportDir.appendingPathComponent("notes.txt.migrated"))
        notes = []
    }

    private func scheduleFlush() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// Writes edited notes. A note's file is named after its first line and renamed as that changes.
    private func flush() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for id in dirty {
            guard let i = notes.firstIndex(where: { $0.id == id }) else { continue }
            let note = notes[i]
            if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let f = note.fileName { try? fm.trashItem(at: folder.appendingPathComponent(f), resultingItemURL: nil) }
                notes[i].fileName = nil
                continue
            }
            let base = Self.safeName(note.title)
            var name = base + ".md"
            var n = 2
            while name != note.fileName, fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                name = "\(base) \(n).md"
                n += 1
            }
            if let old = note.fileName, old != name {
                try? fm.moveItem(at: folder.appendingPathComponent(old), to: folder.appendingPathComponent(name))
            }
            try? note.text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            notes[i].fileName = name
        }
        dirty = []
        rememberSelection()
    }

    private static func safeName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(48)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Actions

    func add() {
        // Reuse an untouched empty note instead of stacking blanks.
        if let empty = notes.first(where: { $0.text.isEmpty }) {
            selectedID = empty.id
        } else {
            let note = Note()
            notes.insert(note, at: 0)
            selectedID = note.id
        }
        showingList = false
    }

    func duplicate(_ note: Note) {
        let copy = Note(text: note.text, date: Date())
        notes.insert(copy, at: 0)
        dirty.insert(copy.id)
        scheduleFlush()
    }

    func select(_ note: Note) { selectedID = note.id; showingList = false; rememberSelection() }

    func delete(_ note: Note) {
        if let f = note.fileName { try? FileManager.default.trashItem(at: folder.appendingPathComponent(f), resultingItemURL: nil) }
        notes.removeAll { $0.id == note.id }
        dirty.remove(note.id)
        if notes.isEmpty { notes = [Note()] }
        if selectedIndex == nil { selectedID = notes.first?.id }
    }

    func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { self.notes.first { $0.id == id }?.text ?? "" },
            set: { new in
                guard let i = self.notes.firstIndex(where: { $0.id == id }) else { return }
                self.notes[i].text = new
                self.notes[i].date = Date()
                self.dirty.insert(id)
                self.scheduleFlush()
            }
        )
    }
}

// MARK: - Shared model

final class AppModel {
    static let shared = AppModel()
    let clipboard = ClipboardStore()
    let files = FilesStore()
    let notes = NotesStore()
    let layout = DrawerLayout()
    var hideDrawer: () -> Void = {}
    var hideDrawerThen: (@escaping () -> Void) -> Void = { $0() }
    var openSettings: (Pane?) -> Void = { _ in }
    var showOnboarding: () -> Void = {}
    /// True while an options popover is open, so the auto-close timer does not run under it.
    var popoverOpen = false
    /// The app that was frontmost when the drawer opened; pasted text goes there.
    var previousApp: NSRunningApplication?

    /// Use a clipboard item: copy it, close the drawer, and paste into the app underneath when allowed.
    func use(_ clip: Clip, paste: Bool? = nil) {
        let s = Settings.shared.v
        clipboard.copy(clip)
        if s.sounds { NSSound(named: "Pop")?.play() }
        let wantsPaste = paste ?? (s.pasteMode == .activeApp)
        if wantsPaste, !Paster.trusted { Paster.requestTrust() }
        hideDrawerThen { [weak self] in
            guard wantsPaste, Paster.trusted else { return }
            if let app = self?.previousApp, NSWorkspace.shared.frontmostApplication != app {
                app.activate(options: [])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Paster.pasteNow() }
        }
    }

    /// Re-read anything that can change outside the app.
    func refresh() {
        clipboard.expanded = nil
        clipboard.refreshIfChanged()
        files.reload()
        notes.refreshIfClean()
        notes.drawerOpened()
    }
}

final class DrawerLayout: ObservableObject {
    /// Space reserved at the top so content clears the menu bar / camera notch.
    @Published var topInset: CGFloat = 14
}
