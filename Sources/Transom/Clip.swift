import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

// One clipboard item and how it is classified (its category and title), plus the time filter.

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
    /// A password or secret: shown masked, never written to disk or synced, and removed after `ClipboardStore.sensitiveLifetime`.
    var sensitive = false
    /// When this item became sensitive: the countdown to its removal starts here, not at the copy (an old item can be marked later).
    /// Memory only, like the rest of what makes an item sensitive.
    var sensitiveSince: Date?
    /// What a marked item was ("link", "image", "file"), so its card can say "Sensitive link" without showing it. Memory only.
    var sensitiveAbout: String?
    /// The picture of a sensitive image, kept in memory so it can still be pasted after its file is deleted. Never written out.
    var heldImage: Data?

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, markdown, imageFile, paths, sourceApp, sourceBundleID, linkTitle, linkImageFile, date, pinned
    }

    /// The saved cover image of a link, if it is on this Mac (see `LinkPreviews`).
    var linkImageURL: URL? {
        guard !sensitive, let name = linkImageFile else { return nil }
        let url = LinkPreviews.folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var imageURL: URL? { sensitive ? nil : imageFile.map { ClipboardFolder.imageURL($0) } }
    var fileURLs: [URL] { (paths ?? []).map { URL(fileURLWithPath: $0) } }
    /// What a card says its kind is: a sensitive item says so instead of "Text".
    var kindLabel: String { sensitive ? "Sensitive" : category.label }
    var kindSymbol: String { sensitive ? "lock.fill" : category.symbol }
    /// When a sensitive item is removed.
    var sensitiveExpiry: Date? { sensitive ? (sensitiveSince ?? date).addingTimeInterval(ClipboardStore.sensitiveLifetime) : nil }
    /// "Sensitive link", "Sensitive image": says what it is without showing it.
    var sensitiveTitle: String { "Sensitive " + (sensitiveAbout ?? "item") }
    /// The file used for the card's cover art.
    var previewURL: URL? { sensitive ? nil : (imageURL ?? linkImageURL ?? fileURLs.first) }
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
            if sensitive { return .text }
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
        if sensitive { return sensitiveTitle }
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
