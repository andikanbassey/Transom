import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct Clip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image, file }
    var id = UUID()
    var kind: Kind
    var text: String?
    /// Set when the copied text had formatting: the same text as Markdown, kept for pasting back with its styling.
    var markdown: String?
    var imageFile: String?
    var paths: [String]?
    var sourceApp: String?
    var sourceBundleID: String?
    var linkTitle: String?
    var linkImageFile: String?
    var date = Date()
    var pinned = false
    /// When this item last changed (copied again, pinned, preview fetched). Newest wins when two Macs disagree.
    var modified = Date()

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, markdown, imageFile, paths, sourceApp, sourceBundleID, linkTitle, linkImageFile, date, pinned
    }

    /// The saved cover image of a link, if it is on this Mac (see `LinkPreviews`).
    var linkImageURL: URL? {
        guard let name = linkImageFile else { return nil }
        let url = LinkPreviews.folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var imageURL: URL? { imageFile.map { ClipboardFolder.images.appendingPathComponent($0) } }
    var fileURLs: [URL] { (paths ?? []).map { URL(fileURLWithPath: $0) } }
    /// The file used for the card's cover art.
    var previewURL: URL? { imageURL ?? linkImageURL ?? fileURLs.first }
}

/// What a clip looks like to the user. Drives the card colour, label and preview style.
enum Category {
    case text, link, color, image, gif, video, audio, pdf, folder, file

    var label: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .color: "Color"
        case .image: "Image"
        case .gif: "GIF"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        case .folder: "Folder"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .color: "paintpalette.fill"
        case .image: "photo"
        case .gif: "photo.stack"
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .folder: "folder.fill"
        case .file: "doc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .text: Color(red: 0.33, green: 0.48, blue: 0.92)
        case .link: Color(red: 0.12, green: 0.62, blue: 0.68)
        case .color: Color(red: 0.88, green: 0.32, blue: 0.55)
        case .image: Color(red: 0.55, green: 0.38, blue: 0.90)
        case .gif: Color(red: 0.76, green: 0.30, blue: 0.80)
        case .video: Color(red: 0.88, green: 0.30, blue: 0.30)
        case .audio: Color(red: 0.36, green: 0.40, blue: 0.80)
        case .pdf: Color(red: 0.90, green: 0.45, blue: 0.22)
        case .folder: Color(red: 0.86, green: 0.62, blue: 0.14)
        case .file: Color(red: 0.45, green: 0.50, blue: 0.56)
        }
    }

    enum Filter: String, CaseIterable {
        case all = "All", text = "Text", links = "Links", images = "Images", color = "Color", video = "Video", files = "Files"
    }

    func matches(_ f: Filter) -> Bool {
        switch f {
        case .all: true
        case .text: self == .text
        case .links: self == .link
        case .images: self == .image || self == .gif
        case .color: self == .color
        case .video: self == .video
        case .files: [.audio, .pdf, .folder, .file].contains(self)
        }
    }
}

extension Clip {
    var category: Category {
        switch kind {
        case .image: return .image
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if Clip.hexColor(t) != nil { return .color }
            if !t.contains(where: \.isWhitespace), let u = URL(string: t), u.host != nil,
               ["http", "https"].contains(u.scheme?.lowercased() ?? "") { return .link }
            return .text
        case .file:
            guard let url = fileURLs.first else { return .file }
            var isDir: ObjCBool = false
            let ext = url.pathExtension.lowercased()
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, ext != "app" { return .folder }
            if ext == "gif" { return .gif }
            guard let type = UTType(filenameExtension: ext) else { return .file }
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .pdf) { return .pdf }
            return .file
        }
    }

    /// File name for files, first lines for text: what the row shows next to the cover art.
    var title: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch category {
            case .link:
                if let title = linkTitle, !title.isEmpty { return title }
                guard let u = URL(string: t), let host = u.host else { return t }
                let path = u.path == "/" ? "" : u.path
                return host.replacingOccurrences(of: "www.", with: "") + path
            case .color: return t.uppercased()
            default: return String(t.prefix(160))
            }
        case .image:
            return imageURL.flatMap(Thumbs.dimensions).map { "Image · \($0)" } ?? "Image"
        case .file:
            guard let first = fileURLs.first else { return "File" }
            return fileURLs.count > 1 ? "\(first.lastPathComponent) + \(fileURLs.count - 1) more" : first.lastPathComponent
        }
    }

    static func hexColor(_ s: String) -> Color? {
        guard s.hasPrefix("#") else { return nil }
        var h = String(s.dropFirst())
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }
}

enum TimeFilter: String, CaseIterable {
    case any = "Any time", hour = "Last hour", today = "Today", week = "This week", month = "This month"

    func includes(_ date: Date, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch self {
        case .any: return true
        case .hour: return now.timeIntervalSince(date) <= 3600
        case .today: return cal.isDateInToday(date)
        case .week: return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .month: return cal.isDate(date, equalTo: now, toGranularity: .month)
        }
    }
}

final class ClipboardStore: ObservableObject {
    @Published var clips: [Clip] = []
    // Filter state lives here so quick paste (⌘1–9) sees the same list the column shows.
    @Published var query = ""
    @Published var searching = false
    @Published var pinnedOnly = false
    @Published var filter = Category.Filter.all
    /// Library only: show clips copied from one app (see `appKey`). Nil shows every app.
    @Published var appFilter: String?
    /// Narrow the Library's clipboard page to a window of time.
    @Published var time = TimeFilter.any
    /// The item the keyboard has selected in the drawer (arrows move it, Return pastes it).
    @Published var cursor: UUID?
    /// The clip shown in full in place of the list, when clicking is set to expand.
    @Published var expanded: Clip?

    /// Months whose Markdown file needs rewriting, and the folder and file state the clips were loaded from.
    private var dirtyMonths = Set<String>()
    private var loadedFolder = ClipboardFolder.url.path
    private var loadedSignature = ""
    private var cancellable: AnyCancellable?
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var settings: SettingsValues { Settings.shared.v }
    private let confidentialTypes: Set<String> = ["org.nspasteboard.ConcealedType", "com.agilebits.onepassword"]
    private let transientTypes: Set<String> = ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]

    init() {
        // History is read in the background: a month file that iCloud has moved out of this Mac can take a long time to
        // come back, and the app must still start (menu bar icon, drawer) while it does.
        load()
        cancellable = Settings.shared.$v.sink { [weak self] _ in
            DispatchQueue.main.async { self?.folderMayHaveChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.trim() }
        // History changed on another Mac arrives as a changed file: pick it up within seconds.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refreshIfChanged() }
    }

    // MARK: Storage

    private let diskQueue = DispatchQueue(label: "studioab.drawer.clipboard-disk", qos: .userInitiated)
    private let imageQueue = DispatchQueue(label: "studioab.drawer.clipboard-images", qos: .utility)
    private var loading = false
    private var isLoaded = false
    private var loadGeneration = 0

    /// Reads the history from disk off the main thread, then merges it in. Reads and writes share one queue, so a load
    /// always sees a save that was started before it.
    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        let started = Date()
        loading = true
        diskQueue.async { [weak self] in
            ClipboardFolder.prepare()
            ClipboardFolder.pruneTombstones()
            let dead = ClipboardFolder.tombstones()
            var best: [UUID: Clip] = [:]
            var fileCount: [String: Int] = [:]
            for file in ClipboardFolder.monthFiles() {
                fileCount[String(file.lastPathComponent.prefix(7)), default: 0] += 1
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for c in ClipHistoryFile.parse(text) where best[c.id].map({ $0.modified < c.modified }) ?? true { best[c.id] = c }
            }
            let loaded = best.values.filter { c in dead[c.id].map { $0 < c.modified } ?? true }.sorted { $0.date > $1.date }
            let folder = ClipboardFolder.url.path
            let signature = ClipboardFolder.signature
            DispatchQueue.main.async {
                guard let self, generation == self.loadGeneration else { return }
                // Keep anything copied or changed while the files were being read.
                let known = Set(loaded.map(\.id))
                let recent = self.clips.filter { !known.contains($0.id) && $0.modified >= started }
                self.clips = (recent + loaded).sorted { $0.date > $1.date }
                // A month with more than one file has sync conflict copies: saving merges them into one.
                self.dirtyMonths.formUnion(fileCount.filter { $0.value > 1 }.keys)
                self.loadedFolder = folder
                self.loadedSignature = signature
                self.loading = false
                if !self.dirtyMonths.isEmpty { self.save() }
                if !self.isLoaded {
                    self.isLoaded = true
                    self.migrateLegacyHistory()
                    self.trim()
                    let snapshot = self.clips
                    self.diskQueue.async { LinkPreviews.tidy(clips: snapshot) }
                    self.refetchMissingPreviews()
                }
            }
        }
    }

    /// History from builds before Markdown storage lived in clips.json with pictures in an images folder.
    private func migrateLegacyHistory() {
        let fm = FileManager.default
        let legacy = supportDir.appendingPathComponent("clips.json")
        guard clips.isEmpty, let data = try? Data(contentsOf: legacy), let old = try? JSONDecoder().decode([Clip].self, from: data) else { return }
        let oldImages = supportDir.appendingPathComponent("images")
        for name in (try? fm.contentsOfDirectory(atPath: oldImages.path)) ?? [] {
            try? fm.copyItem(at: oldImages.appendingPathComponent(name), to: ClipboardFolder.images.appendingPathComponent(name))
        }
        clips = old
        for c in old { dirtyMonths.insert(ClipboardFolder.monthKey(c.date)) }
        save()
        try? fm.moveItem(at: legacy, to: supportDir.appendingPathComponent("clips.json.migrated"))
    }

    /// The storage folder moved (for example to iCloud Drive): bring the history along unless the new place has its own.
    private func folderMayHaveChanged() {
        let now = ClipboardFolder.url
        guard now.path != loadedFolder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: now, withIntermediateDirectories: true)
        let hasHistory = !(((try? fm.contentsOfDirectory(atPath: now.path)) ?? []).filter { $0.hasSuffix(".md") }.isEmpty)
        if !hasHistory {
            let old = URL(fileURLWithPath: loadedFolder)
            for item in (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.copyItem(at: item, to: now.appendingPathComponent(item.lastPathComponent))
            }
        }
        load()
    }

    /// Pick up history changed outside the app (another Mac through iCloud). Called when the drawer opens.
    func refreshIfChanged() {
        guard isLoaded, !loading, dirtyMonths.isEmpty, ClipboardFolder.signature != loadedSignature else { return }
        load()
    }

    func moveCursor(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        if let current = list.firstIndex(where: { $0.id == cursor }) {
            cursor = list[min(max(current + delta, 0), list.count - 1)].id
        } else {
            cursor = list[delta > 0 ? 0 : list.count - 1].id
        }
    }

    var cursorClip: Clip? { visible.first { $0.id == cursor } }

    /// The clips the column shows: filtered, pinned first.
    var visible: [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = clips.filter { clip in
            clip.category.matches(filter)
                && time.includes(clip.date)
                && (appFilter == nil || Self.appKey(clip) == appFilter)
                && (!pinnedOnly || clip.pinned)
                && (q.isEmpty || clip.title.localizedCaseInsensitiveContains(q)
                    || (clip.sourceApp ?? "").localizedCaseInsensitiveContains(q))
        }
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    /// Items bigger than this are not stored: they would bloat the history and slow every launch.
    static let maxTextBytes = 5_000_000
    static let maxImageBytes = 60_000_000

    private func poll() {
        // Until the history is in, leave the pasteboard alone: what is on it now is picked up as soon as it is.
        guard isLoaded else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let s = settings
        let app = NSWorkspace.shared.frontmostApplication
        let isSelf = app?.bundleIdentifier == Bundle.main.bundleIdentifier
        let who = isSelf ? "Drawer" : (app?.localizedName ?? "Unknown app")
        let log = CaptureLog.shared
        if AppModel.shared.standby { log.add(app: who, result: "Skipped: another Drawer is active"); return }
        if s.paused { log.add(app: who, result: "Skipped: capture is paused"); return }
        let types = Set((pb.types ?? []).map(\.rawValue))
        if s.ignoreConfidential, !types.isDisjoint(with: confidentialTypes) { log.add(app: who, result: "Skipped: marked confidential"); return }
        if s.ignoreTransient, !types.isDisjoint(with: transientTypes) { log.add(app: who, result: "Skipped: marked transient"); return }
        if !isSelf, !Settings.shared.allows(bundleID: app?.bundleIdentifier) { log.add(app: who, result: "Skipped: app is not allowed"); return }
        var base = Clip(kind: .text)
        base.sourceApp = isSelf ? nil : app?.localizedName
        base.sourceBundleID = isSelf ? nil : app?.bundleIdentifier

        // Files first: Finder also puts the file name on the pasteboard as text.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            var clip = base
            clip.kind = .file
            clip.paths = urls.map(\.path)
            insert(clip, replacing: { $0.paths == clip.paths })
            log.add(app: who, result: "Stored: \(urls.count == 1 ? "file" : "\(urls.count) files")")
        } else if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard str.utf8.count <= Self.maxTextBytes else {
                log.add(app: who, result: "Skipped: text over \(Self.maxTextBytes / 1_000_000) MB")
                return
            }
            var clip = base
            clip.text = str
            clip.markdown = Self.richMarkdown(pb)
            insert(clip, replacing: { $0.kind == .text && $0.text == str })
            log.add(app: who, result: "Stored: text (\(str.count) characters)")
            if s.linkPreviews, clips.first?.category == .link, clips.first?.linkTitle == nil,
               let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)), let id = clips.first?.id {
                fetchPreview(id: id, url: url)
            }
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            guard data.count <= Self.maxImageBytes else {
                log.add(app: who, result: "Skipped: image over \(Self.maxImageBytes / 1_000_000) MB")
                return
            }
            storeImage(data, alreadyPNG: pb.data(forType: .png) != nil, base: base, who: who)
        } else {
            log.add(app: who, result: "Skipped: nothing Drawer can store (\(types.first ?? "empty"))")
        }
    }

    /// Encoding a large screenshot takes a moment: do it off the main thread, then add the item.
    /// Saves a copied picture. The same picture copied again (byte for byte, among the newest pictures) is not stored twice:
    /// the earlier item moves to the top and keeps its file.
    func storeImage(_ data: Data, alreadyPNG: Bool, base: Clip, who: String) {
        ClipboardFolder.prepare()
        let name = UUID().uuidString + ".png"
        let dest = ClipboardFolder.images.appendingPathComponent(name)
        let candidates = clips.filter { $0.kind == .image }.prefix(60).compactMap(\.imageFile)
        imageQueue.async { [weak self] in
            guard let png = alreadyPNG ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else {
                DispatchQueue.main.async { CaptureLog.shared.add(app: who, result: "Failed: could not save the image") }
                return
            }
            var existing: String?
            for file in candidates {
                let url = ClipboardFolder.images.appendingPathComponent(file)
                // Same size first, and only files already on this Mac: never wait on an iCloud download for this.
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size == png.count,
                      ClipboardFolder.isOnThisMac(url), let old = try? Data(contentsOf: url), old == png else { continue }
                existing = file
                break
            }
            let saved = existing != nil || (try? png.write(to: dest)) != nil
            DispatchQueue.main.async {
                guard saved else { CaptureLog.shared.add(app: who, result: "Failed: could not save the image"); return }
                var clip = base
                clip.kind = .image
                clip.imageFile = existing ?? name
                if let existing {
                    self?.insert(clip, replacing: { $0.kind == .image && $0.imageFile == existing })
                    CaptureLog.shared.add(app: who, result: "Stored: image (same as an earlier one, moved to the top)")
                } else {
                    self?.insert(clip, replacing: { _ in false })
                    CaptureLog.shared.add(app: who, result: "Stored: image")
                }
            }
        }
    }

    private func insert(_ clip: Clip, replacing match: (Clip) -> Bool) {
        var clip = clip
        if let i = clips.firstIndex(where: match) {
            clip.pinned = clips[i].pinned
            clip.linkTitle = clips[i].linkTitle
            clip.linkImageFile = clips[i].linkImageFile
            dirtyMonths.insert(ClipboardFolder.monthKey(clips[i].date))
            // The older copy of the same thing is replaced, so other Macs must not bring it back.
            ClipboardFolder.addTombstone(clips[i].id)
            clips.remove(at: i)
        }
        clips.insert(clip, at: 0)
        dirtyMonths.insert(ClipboardFolder.monthKey(clip.date))
        trim()
    }

    /// Drop unpinned items past the retention window or the item limit.
    func trim() {
        if let interval = settings.retention.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            for i in clips.indices.reversed() where !clips[i].pinned && clips[i].date < cutoff { remove(at: i) }
        }
        save()
    }

    // MARK: Link previews

    private func fetchPreview(id: UUID, url: URL) {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 Drawer", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            let head = Data(data.prefix(300_000))
            guard let html = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else { return }
            let title = Self.meta(html, "og:title") ?? Self.firstMatch(html, #"<title[^>]*>([^<]*)</title>"#)
            let imageRef = Self.meta(html, "og:image")
            let finish: (String?) -> Void = { imageFile in
                DispatchQueue.main.async {
                    guard let i = self.clips.firstIndex(where: { $0.id == id }) else { return }
                    self.clips[i].linkTitle = title.map(Self.decodeEntities)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.clips[i].linkImageFile = imageFile
                    self.clips[i].modified = Date()
                    self.dirtyMonths.insert(ClipboardFolder.monthKey(self.clips[i].date))
                    self.save()
                }
            }
            guard let ref = imageRef, let imgURL = URL(string: Self.decodeEntities(ref), relativeTo: url)?.absoluteURL else { return finish(nil) }
            URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                var name: String?
                if let imgData, let png = NSBitmapImageRep(data: imgData)?.representation(using: .png, properties: [:]) {
                    let n = UUID().uuidString + ".png"
                    LinkPreviews.prepare()
                    if (try? png.write(to: LinkPreviews.folder.appendingPathComponent(n))) != nil { name = n }
                }
                finish(name)
            }.resume()
        }.resume()
    }

    /// Covers are not synced, so a link copied on another Mac has none here yet: fetch the newest few again, under the
    /// same file names, without touching the history.
    private func refetchMissingPreviews() {
        guard settings.linkPreviews else { return }
        let missing = clips.filter { $0.category == .link && $0.linkImageFile != nil && $0.linkImageURL == nil }.prefix(30)
        for clip in missing {
            guard let name = clip.linkImageFile, let text = clip.text,
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 Drawer", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data else { return }
                let head = Data(data.prefix(300_000))
                guard let html = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1),
                      let ref = Self.meta(html, "og:image"),
                      let imgURL = URL(string: Self.decodeEntities(ref), relativeTo: url)?.absoluteURL else { return }
                URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                    guard let imgData, let png = NSBitmapImageRep(data: imgData)?.representation(using: .png, properties: [:]) else { return }
                    LinkPreviews.prepare()
                    try? png.write(to: LinkPreviews.folder.appendingPathComponent(name))
                    DispatchQueue.main.async { self.objectWillChange.send() }
                }.resume()
            }.resume()
        }
    }

    private static func meta(_ html: String, _ key: String) -> String? {
        firstMatch(html, #"<meta[^>]+(?:property|name)=["']"# + key + #"["'][^>]*content=["']([^"']*)["']"#)
            ?? firstMatch(html, #"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']"# + key + #"["']"#)
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        let value = String(text[r])
        return value.isEmpty ? nil : value
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: Actions

    func copy(_ clip: Clip, plain: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.kind {
        case .text:
            if let md = clip.markdown, !plain {
                pb.writeObjects([RichText.attributed(fromMarkdown: md)])
            } else {
                pb.setString(clip.text ?? "", forType: .string)
            }
        case .file: pb.writeObjects(clip.fileURLs as [NSURL])
        case .image:
            // Put the stored PNG back as it is. Handing macOS an NSImage instead makes it offer uncompressed TIFF,
            // so Finder pasted a 27 MB .tiff for a 2 MB screenshot.
            if let url = clip.imageURL, let data = try? Data(contentsOf: url) { pb.setData(data, forType: .png) }
        }
        lastCount = pb.changeCount
        if let i = clips.firstIndex(of: clip) {
            var moved = clips.remove(at: i)
            dirtyMonths.insert(ClipboardFolder.monthKey(moved.date))
            moved.date = Date()
            moved.modified = Date()
            dirtyMonths.insert(ClipboardFolder.monthKey(moved.date))
            clips.insert(moved, at: 0)
            save()
        }
    }

    func togglePin(_ clip: Clip) {
        guard let i = clips.firstIndex(of: clip) else { return }
        clips[i].pinned.toggle()
        clips[i].modified = Date()
        dirtyMonths.insert(ClipboardFolder.monthKey(clips[i].date))
        save()
    }

    func delete(_ clip: Clip) {
        guard let i = clips.firstIndex(of: clip) else { return }
        remove(at: i, tombstone: true)
        save()
    }

    /// Delete many at once (Library selection): one save for the lot.
    func delete(ids: Set<UUID>) {
        for i in clips.indices.reversed() where ids.contains(clips[i].id) { remove(at: i, tombstone: true) }
        save()
    }

    func setPinned(_ pinned: Bool, ids: Set<UUID>) {
        for i in clips.indices where ids.contains(clips[i].id) && clips[i].pinned != pinned {
            clips[i].pinned = pinned
            clips[i].modified = Date()
            dirtyMonths.insert(ClipboardFolder.monthKey(clips[i].date))
        }
        save()
    }

    func clearUnpinned() {
        for i in clips.indices.reversed() where !clips[i].pinned { remove(at: i, tombstone: true) }
        save()
    }

    func eraseAll() {
        for i in clips.indices.reversed() { remove(at: i, tombstone: true) }
        save()
    }

    private func remove(at i: Int, tombstone: Bool = false) {
        if tombstone { ClipboardFolder.addTombstone(clips[i].id) }
        if let file = clips[i].imageFile { try? FileManager.default.removeItem(at: ClipboardFolder.images.appendingPathComponent(file)) }
        if let file = clips[i].linkImageFile { try? FileManager.default.removeItem(at: LinkPreviews.folder.appendingPathComponent(file)) }
        dirtyMonths.insert(ClipboardFolder.monthKey(clips[i].date))
        clips.remove(at: i)
    }

    /// Rewrite only the months that changed. Each month is merged with what is on disk first, so another Mac's
    /// additions and changes (arriving through iCloud) are kept: newest change per item wins, deletions stay deleted.
    private func save() {
        guard !dirtyMonths.isEmpty else { return }
        let months = dirtyMonths
        let snapshot = clips
        dirtyMonths = []
        diskQueue.async { [weak self] in
            Self.write(months: months, clips: snapshot)
            let signature = ClipboardFolder.signature
            DispatchQueue.main.async { self?.loadedSignature = signature }
        }
    }

    /// Rewrites the given months, each merged with what is on disk first (see `save`). Runs on the disk queue.
    private static func write(months: Set<String>, clips: [Clip]) {
        ClipboardFolder.prepare()
        let dead = ClipboardFolder.tombstones()
        let mine = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byMonth = Dictionary(grouping: clips, by: { ClipboardFolder.monthKey($0.date) })
        for month in months {
            let canonical = ClipboardFolder.fileURL(month: month)
            let files = ClipboardFolder.files(forMonth: month)
            var merged: [UUID: Clip] = [:]
            for file in files {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for c in ClipHistoryFile.parse(text) {
                    // Copied again on this Mac, so it now belongs to a later month.
                    if let m = mine[c.id], ClipboardFolder.monthKey(m.date) != month { continue }
                    if let old = merged[c.id], old.modified >= c.modified { continue }
                    merged[c.id] = c
                }
            }
            for c in byMonth[month] ?? [] {
                if let old = merged[c.id], old.modified > c.modified { continue }
                merged[c.id] = c
            }
            let items = merged.values.filter { c in dead[c.id].map { $0 < c.modified } ?? true }
            if items.isEmpty {
                for f in files { try? FileManager.default.removeItem(at: f) }
            } else {
                try? ClipHistoryFile.render(month: month, clips: Array(items)).write(to: canonical, atomically: true, encoding: .utf8)
                for f in files where f != canonical { try? FileManager.default.removeItem(at: f) }
            }
        }
    }

    /// Markdown for the copied text when it has formatting; rich text first, then HTML.
    private static func richMarkdown(_ pb: NSPasteboard) -> String? {
        if let rtf = pb.data(forType: .rtf), let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return RichText.markdown(from: attr)
        }
        if let html = pb.data(forType: .html), html.count < 200_000,
           let attr = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil) {
            return RichText.markdown(from: attr)
        }
        return nil
    }
}

// MARK: - Cover art

enum Thumbs {
    private static let cache = NSCache<NSString, NSImage>()

    /// QuickLook cover art: first frame of a video or GIF, first page of a PDF, the image itself, or the file icon.
    static func image(for url: URL, size: CGSize) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .all)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return nil }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }

    private static var dimensionCache: [String: String] = [:]
    static func dimensions(_ url: URL) -> String? {
        if let hit = dimensionCache[url.path] { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let s = "\(w) × \(h)"
        dimensionCache[url.path] = s
        return s
    }
}

/// Cover images of copied links. They live on this Mac only (Application Support), not in the synced clipboard folder:
/// they can be fetched again, and keeping them out of iCloud means a deleted link leaves nothing behind to sync.
enum LinkPreviews {
    static var folder: URL { supportDir.appendingPathComponent("LinkPreviews", isDirectory: true) }

    static func prepare() { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    /// Runs on the disk queue after the history is loaded: moves covers an earlier version left in the clipboard folder
    /// into the local folder, and deletes covers no link refers to any more.
    static func tidy(clips: [Clip]) {
        let fm = FileManager.default
        prepare()
        let wanted = Set(clips.compactMap(\.linkImageFile))
        for name in wanted {
            let old = ClipboardFolder.images.appendingPathComponent(name)
            let new = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
            else if fm.fileExists(atPath: old.path) { try? fm.removeItem(at: old) }
        }
        // An empty history may only mean it could not be read yet: never sweep on that.
        guard !clips.isEmpty else { return }
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !wanted.contains(name) && !name.hasPrefix(".") {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

extension ClipboardStore {
    /// What identifies the app a clip came from: its bundle id, or its name when there is none.
    static func appKey(_ clip: Clip) -> String? { clip.sourceBundleID ?? clip.sourceApp }

    /// The apps in the history, most used first, with a name, an icon key and a count, for the Library's App filter.
    var appsInHistory: [(key: String, name: String, bundle: String?, count: Int)] {
        var seen: [String: (name: String, bundle: String?, count: Int)] = [:]
        for c in clips {
            guard let key = Self.appKey(c) else { continue }
            var entry = seen[key] ?? (c.sourceApp ?? key, c.sourceBundleID, 0)
            entry.count += 1
            seen[key] = entry
        }
        return seen.map { (key: $0.key, name: $0.value.name, bundle: $0.value.bundle, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ bundleID: String?) -> NSImage? {
        guard let id = bundleID else { return nil }
        if let hit = cache[id] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[id] = img
        return img
    }
}

/// The last few things the clipboard watcher saw and what it did with them, for finding out why something was not saved.
final class CaptureLog: ObservableObject {
    static let shared = CaptureLog()
    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let app: String
        let result: String
        var line: String { "\(date.formatted(date: .omitted, time: .standard))  \(app): \(result)" }
    }
    @Published private(set) var entries: [Entry] = []

    func add(app: String, result: String) {
        entries.insert(Entry(app: app, result: result), at: 0)
        if entries.count > 40 { entries.removeLast(entries.count - 40) }
    }
    func clear() { entries = [] }
}
