import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct Clip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image, file }
    var id = UUID()
    var kind: Kind
    var text: String?
    var imageFile: String?
    var paths: [String]?
    var sourceApp: String?
    var sourceBundleID: String?
    var linkTitle: String?
    var linkImageFile: String?
    var date = Date()
    var pinned = false

    var linkImageURL: URL? { linkImageFile.map { supportDir.appendingPathComponent("images/\($0)") } }
    var imageURL: URL? { imageFile.map { supportDir.appendingPathComponent("images/\($0)") } }
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
        case all = "All", text = "Text", links = "Links", media = "Media", files = "Files"
    }

    func matches(_ f: Filter) -> Bool {
        switch f {
        case .all: true
        case .text: self == .text || self == .color
        case .links: self == .link
        case .media: self == .image || self == .gif || self == .video
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

final class ClipboardStore: ObservableObject {
    @Published var clips: [Clip] = []
    // Filter state lives here so quick paste (⌘1–9) sees the same list the column shows.
    @Published var query = ""
    @Published var searching = false
    @Published var pinnedOnly = false
    @Published var filter = Category.Filter.all

    private let file = supportDir.appendingPathComponent("clips.json")
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var settings: SettingsValues { Settings.shared.v }
    private let confidentialTypes: Set<String> = ["org.nspasteboard.ConcealedType", "com.agilebits.onepassword"]
    private let transientTypes: Set<String> = ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Clip].self, from: data) {
            clips = saved
        }
        trim()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.trim() }
    }

    /// The clips the column shows: filtered, pinned first.
    var visible: [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = clips.filter { clip in
            clip.category.matches(filter)
                && (!pinnedOnly || clip.pinned)
                && (q.isEmpty || clip.title.localizedCaseInsensitiveContains(q)
                    || (clip.sourceApp ?? "").localizedCaseInsensitiveContains(q))
        }
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let s = settings
        if s.paused { return }
        let types = Set((pb.types ?? []).map(\.rawValue))
        if s.ignoreConfidential, !types.isDisjoint(with: confidentialTypes) { return }
        if s.ignoreTransient, !types.isDisjoint(with: transientTypes) { return }

        let app = NSWorkspace.shared.frontmostApplication
        let isSelf = app?.bundleIdentifier == Bundle.main.bundleIdentifier
        if !isSelf, !Settings.shared.allows(bundleID: app?.bundleIdentifier) { return }
        var base = Clip(kind: .text)
        base.sourceApp = isSelf ? nil : app?.localizedName
        base.sourceBundleID = isSelf ? nil : app?.bundleIdentifier

        // Files first: Finder also puts the file name on the pasteboard as text.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            var clip = base
            clip.kind = .file
            clip.paths = urls.map(\.path)
            insert(clip, replacing: { $0.paths == clip.paths })
        } else if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var clip = base
            clip.text = str
            insert(clip, replacing: { $0.kind == .text && $0.text == str })
            if s.linkPreviews, clips.first?.category == .link, clips.first?.linkTitle == nil,
               let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)), let id = clips.first?.id {
                fetchPreview(id: id, url: url)
            }
        } else if let tiff = pb.data(forType: .tiff) ?? pb.data(forType: .png),
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let name = UUID().uuidString + ".png"
            try? png.write(to: supportDir.appendingPathComponent("images/\(name)"))
            var clip = base
            clip.kind = .image
            clip.imageFile = name
            insert(clip, replacing: { _ in false })
        }
    }

    private func insert(_ clip: Clip, replacing match: (Clip) -> Bool) {
        var clip = clip
        if let i = clips.firstIndex(where: match) {
            clip.pinned = clips[i].pinned
            clip.linkTitle = clips[i].linkTitle
            clip.linkImageFile = clips[i].linkImageFile
            clips.remove(at: i)
        }
        clips.insert(clip, at: 0)
        trim()
    }

    /// Drop unpinned items past the retention window or the item limit.
    func trim() {
        if let interval = settings.retention.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            for i in clips.indices.reversed() where !clips[i].pinned && clips[i].date < cutoff { remove(at: i) }
        }
        while clips.count > settings.historyLimit, let i = clips.lastIndex(where: { !$0.pinned }) { remove(at: i) }
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
                    self.save()
                }
            }
            guard let ref = imageRef, let imgURL = URL(string: Self.decodeEntities(ref), relativeTo: url)?.absoluteURL else { return finish(nil) }
            URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                var name: String?
                if let imgData, let png = NSBitmapImageRep(data: imgData)?.representation(using: .png, properties: [:]) {
                    let n = UUID().uuidString + ".png"
                    if (try? png.write(to: supportDir.appendingPathComponent("images/\(n)"))) != nil { name = n }
                }
                finish(name)
            }.resume()
        }.resume()
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

    func copy(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.kind {
        case .text: pb.setString(clip.text ?? "", forType: .string)
        case .file: pb.writeObjects(clip.fileURLs as [NSURL])
        case .image:
            if let url = clip.imageURL, let img = NSImage(contentsOf: url) { pb.writeObjects([img]) }
        }
        lastCount = pb.changeCount
        if let i = clips.firstIndex(of: clip) {
            var moved = clips.remove(at: i)
            moved.date = Date()
            clips.insert(moved, at: 0)
            save()
        }
    }

    func togglePin(_ clip: Clip) {
        guard let i = clips.firstIndex(of: clip) else { return }
        clips[i].pinned.toggle()
        save()
    }

    func delete(_ clip: Clip) {
        guard let i = clips.firstIndex(of: clip) else { return }
        remove(at: i)
        save()
    }

    func clearUnpinned() {
        for i in clips.indices.reversed() where !clips[i].pinned { remove(at: i) }
        save()
    }

    func eraseAll() {
        for i in clips.indices.reversed() { remove(at: i) }
        save()
    }

    private func remove(at i: Int) {
        for file in [clips[i].imageFile, clips[i].linkImageFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: supportDir.appendingPathComponent("images/\(file)"))
        }
        clips.remove(at: i)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clips) { try? data.write(to: file, options: .atomic) }
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
