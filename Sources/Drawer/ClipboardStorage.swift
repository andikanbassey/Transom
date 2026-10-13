import AppKit
import Foundation

/// Where clipboard history lives: one Markdown file per month, plus an Images folder for pictures that have
/// no file of their own (screenshots, link covers). Follows the storage folder setting, so it can sit in iCloud Drive.
enum ClipboardFolder {
    static var url: URL {
        Settings.shared.v.clipboardFolder.map { URL(fileURLWithPath: $0) } ?? supportDir.appendingPathComponent("Clipboard", isDirectory: true)
    }
    static var images: URL { url.appendingPathComponent("Images", isDirectory: true) }

    static func prepare() {
        try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    }

    static func monthFiles() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func monthKey(_ date: Date) -> String { monthFormatter.string(from: date) }
    static func fileURL(month: String) -> URL { url.appendingPathComponent("\(month).md") }

    /// Changes when a month file is added, removed or edited, including by another Mac through iCloud.
    static var signature: String {
        monthFiles().map { f in
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return "\(f.lastPathComponent):\(d?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "|")
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}

/// Reads and writes a month of history as Markdown. Each entry sits between two comment markers, so the file
/// reads well in any Markdown viewer and round-trips exactly.
enum ClipHistoryFile {
    private struct Meta: Codable {
        var id: UUID
        var kind: Clip.Kind
        var date: Double
        var pinned: Bool?
        var app: String?
        var bundle: String?
        var paths: [String]?
        var image: String?
        var linkTitle: String?
        var linkImage: String?
        var rich: Bool?
    }

    private static let open = "<!-- drawer:clip "
    private static let close = "<!-- /drawer:clip -->"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    // MARK: Write

    static func render(month: String, clips: [Clip]) -> String {
        let encoder = JSONEncoder()
        var out = "# Clipboard \(month)\n"
        var day = ""
        for clip in clips.sorted(by: { $0.date < $1.date }) {
            let d = dayFormatter.string(from: clip.date)
            if d != day { day = d; out += "\n## \(d)\n" }
            let meta = Meta(id: clip.id, kind: clip.kind, date: clip.date.timeIntervalSince1970, pinned: clip.pinned ? true : nil,
                            app: clip.sourceApp, bundle: clip.sourceBundleID, paths: clip.paths, image: clip.imageFile,
                            linkTitle: clip.linkTitle, linkImage: clip.linkImageFile, rich: clip.markdown != nil ? true : nil)
            let json = (try? String(data: encoder.encode(meta), encoding: .utf8)) ?? "{}"
            // "-->" inside the JSON would end the comment early.
            let safeJSON = json.replacingOccurrences(of: "-->", with: "--\\u003e")
            out += "\n### \(timeFormatter.string(from: clip.date)) · \(clip.category.label)"
            if let app = clip.sourceApp { out += " · \(app)" }
            out += "\n\(open)\(safeJSON) -->\n"
            switch clip.kind {
            case .text: out += escape(clip.markdown ?? clip.text ?? "") + "\n"
            case .image: out += "![Image](Images/\(clip.imageFile ?? ""))\n"
            case .file: out += (clip.paths ?? []).map { "- \($0)" }.joined(separator: "\n") + "\n"
            }
            out += close + "\n"
        }
        return out
    }

    /// Lines that look like markers (or already start with a backslash) get a backslash in front.
    private static func escape(_ s: String) -> String {
        s.components(separatedBy: "\n").map { $0.hasPrefix("<!--") || $0.hasPrefix("\\") ? "\\" + $0 : $0 }.joined(separator: "\n")
    }
    private static func unescape(_ lines: [String]) -> String {
        lines.map { $0.hasPrefix("\\") ? String($0.dropFirst()) : $0 }.joined(separator: "\n")
    }

    // MARK: Read

    static func parse(_ text: String) -> [Clip] {
        var clips: [Clip] = []
        var meta: Meta?
        var body: [String] = []
        let decoder = JSONDecoder()
        for line in text.components(separatedBy: "\n") {
            if meta == nil {
                guard line.hasPrefix(open), line.hasSuffix(" -->") else { continue }
                let json = String(line.dropFirst(open.count).dropLast(4))
                meta = try? decoder.decode(Meta.self, from: Data(json.utf8))
                body = []
            } else if line == close {
                if let m = meta { clips.append(clip(from: m, body: unescape(body))) }
                meta = nil
            } else {
                body.append(line)
            }
        }
        return clips
    }

    private static func clip(from m: Meta, body: String) -> Clip {
        var clip = Clip(kind: m.kind)
        clip.id = m.id
        clip.date = Date(timeIntervalSince1970: m.date)
        clip.pinned = m.pinned ?? false
        clip.sourceApp = m.app
        clip.sourceBundleID = m.bundle
        clip.paths = m.paths
        clip.imageFile = m.image
        clip.linkTitle = m.linkTitle
        clip.linkImageFile = m.linkImage
        if m.kind == .text {
            if m.rich == true {
                clip.markdown = body
                clip.text = RichText.attributed(fromMarkdown: body).string
            } else {
                clip.text = body
            }
        }
        return clip
    }
}

/// Converts between formatted text on the pasteboard and the Markdown stored in history.
enum RichText {
    /// Markdown for the text's bold, italic, strikethrough, code and links. Nil when it has no formatting,
    /// so plain text is stored exactly as copied.
    static func markdown(from attr: NSAttributedString) -> String? {
        guard attr.length > 0, attr.length < 200_000 else { return nil }
        let fm = NSFontManager.shared
        var out = ""
        var formatted = false
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
            let run = (attr.string as NSString).substring(with: range)
            let trimmed = run.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let core = run.range(of: trimmed) else { out += escapePlain(run); return }
            let lead = String(run[run.startIndex..<core.lowerBound]), trail = String(run[core.upperBound...])
            var text = escapePlain(trimmed)
            var wraps: [String] = []
            if let font = attrs[.font] as? NSFont {
                let traits = fm.traits(of: font)
                if font.isFixedPitch { text = trimmed; wraps.append("`") }
                else {
                    if traits.contains(.boldFontMask) && traits.contains(.italicFontMask) { wraps.append("***") }
                    else if traits.contains(.boldFontMask) { wraps.append("**") }
                    else if traits.contains(.italicFontMask) { wraps.append("*") }
                }
            }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { wraps.append("~~") }
            for w in wraps { text = w + text + w }
            if let link = attrs[.link] {
                let url = (link as? URL)?.absoluteString ?? (link as? String)
                if let url { text = "[\(text)](\(url))"; wraps.append("link") }
            }
            if !wraps.isEmpty { formatted = true }
            out += lead + text + trail
        }
        return formatted ? out : nil
    }

    private static func escapePlain(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\*_`[]~".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Rebuild formatted text from stored Markdown, for pasting back with its styling.
    static func attributed(fromMarkdown md: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: md, options: options) else { return NSAttributedString(string: md) }
        let base = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let fm = NSFontManager.shared
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var attrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: NSColor.textColor]
            var font = base
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular) }
                if intent.contains(.stronglyEmphasized) { font = fm.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = fm.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            attrs[.font] = font
            if let link = run.link { attrs[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attrs))
        }
        return result
    }
}
