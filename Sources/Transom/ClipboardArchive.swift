import Foundation

/// Where items go when the "Keep history" setting expires them: one Markdown file per hour they were archived, plus
/// their pictures, kept for `keepDays` and then deleted for good. It lives on this Mac only (never in a synced folder),
/// so retention frees the synced history while a mistake can still be undone by hand for a while.
enum ClipboardArchive {
    static let keepDays = 90

    static var folder: URL { supportDir.appendingPathComponent("ClipboardArchive", isDirectory: true) }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HH"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let prefix = "archived-"

    private static func file(on day: Date, in folder: URL) -> URL {
        folder.appendingPathComponent("\(prefix)\(dayFormatter.string(from: day)).md")
    }

    /// How far back "Restore removed items" reaches, counted from when the items were removed.
    enum Range: CaseIterable {
        case pastHour, today, thisWeek, thisMonth, all
        var label: String {
            switch self {
            case .pastHour: "Past hour"
            case .today: "Today"
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .all: "Everything (\(ClipboardArchive.keepDays) days)"
            }
        }
        func start(now: Date = Date()) -> Date? {
            let cal = Calendar.current
            switch self {
            case .pastHour: return now.addingTimeInterval(-3600)
            case .today: return cal.startOfDay(for: now)
            case .thisWeek: return cal.dateInterval(of: .weekOfYear, for: now)?.start
            case .thisMonth: return cal.dateInterval(of: .month, for: now)?.start
            case .all: return nil
            }
        }
    }

    /// Archive files with the hour they were written for. A file counts for a range if any part of its hour is inside it.
    private static func files(since start: Date?, in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { url in
            guard url.pathExtension == "md", url.lastPathComponent.hasPrefix(prefix),
                  let hour = dayFormatter.date(from: String(url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count))) else { return false }
            return start.map { hour.addingTimeInterval(3600) > $0 } ?? true
        }
    }

    /// How many items each range would bring back. Counts markers instead of parsing, so it is quick even for a big archive.
    static func counts(now: Date = Date(), in folder: URL = folder) -> [Range: Int] {
        var out: [Range: Int] = [:]
        for range in Range.allCases {
            out[range] = files(since: range.start(now: now), in: folder).reduce(0) { sum, url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return sum + text.components(separatedBy: "<!-- drawer:clip ").count - 1
            }
        }
        return out
    }

    /// Takes the items of a range out of the archive and puts their pictures back in `pictures`. Runs on the disk queue.
    static func restore(_ range: Range, now: Date = Date(), in folder: URL = folder, pictures: URL = ClipboardFolder.imageWriteFolder) -> [Clip] {
        let fm = FileManager.default
        try? fm.createDirectory(at: pictures, withIntermediateDirectories: true)
        var out: [Clip] = []
        for url in files(since: range.start(now: now), in: folder) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let clips = ClipHistoryFile.parse(text)
            for name in clips.compactMap(\.imageFile) {
                let from = folder.appendingPathComponent("Images").appendingPathComponent(name)
                if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: pictures.appendingPathComponent(name)) }
            }
            out += clips
            try? fm.removeItem(at: url)
        }
        return out
    }

    /// Adds the clips to this hour's archive file and moves their pictures next to it. Runs on the disk queue.
    static func store(_ clips: [Clip], on day: Date = Date(), in folder: URL = folder,
                      pictureURL: (String) -> URL = ClipboardFolder.imageURL) {
        guard !clips.isEmpty else { return }
        let fm = FileManager.default
        let pictures = folder.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: pictures, withIntermediateDirectories: true)
        for name in clips.compactMap(\.imageFile) {
            let from = pictureURL(name), to = pictures.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) { try? fm.moveItem(at: from, to: to) }
            else { try? fm.removeItem(at: from) }
        }
        let target = file(on: day, in: folder)
        var merged: [UUID: Clip] = [:]
        if let text = try? String(contentsOf: target, encoding: .utf8) { for c in ClipHistoryFile.parse(text) { merged[c.id] = c } }
        for c in clips { merged[c.id] = c }
        let title = "archived \(dayFormatter.string(from: day))"
        try? ClipHistoryFile.render(month: title, clips: Array(merged.values)).write(to: target, atomically: true, encoding: .utf8)
    }

    /// Deletes archive files older than `keepDays`, with the pictures they refer to.
    static func purge(now: Date = Date(), in folder: URL = folder) {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86400)
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "md" && url.lastPathComponent.hasPrefix(prefix) {
            let stamp = url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count)
            guard let day = dayFormatter.date(from: String(stamp)), day < cutoff else { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                for name in ClipHistoryFile.parse(text).compactMap(\.imageFile) {
                    try? fm.removeItem(at: folder.appendingPathComponent("Images").appendingPathComponent(name))
                }
            }
            try? fm.removeItem(at: url)
        }
    }
}
