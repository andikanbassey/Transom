import CryptoKit
import Foundation

/// What is known about a history item without holding its text: enough to choose what to load, count it and spot a repeat copy.
struct ClipRecord: Codable, Equatable {
    var id: UUID
    var date: Date
    var modified: Date
    var pinned: Bool
    var identity: UUID?
    var app: String?
    var bundle: String?

    init(_ clip: Clip) {
        id = clip.id
        date = clip.date
        modified = clip.modified
        pinned = clip.pinned
        identity = Self.identity(of: clip)
        app = clip.sourceApp
        bundle = clip.sourceBundleID
    }

    /// The moment retention counts from: a restored item keeps its old date but counts from when it was restored.
    var touched: Date { max(date, modified) }

    /// Two items with the same identity are the same copied thing. Pictures have none: they are compared by their files.
    static func identity(of clip: Clip) -> UUID? {
        switch clip.kind {
        case .text: return clip.text.map { hash("text\0" + Clip.contentKey($0)) }
        case .file: return clip.paths.map { hash("file\0" + $0.joined(separator: "\0")) }
        case .image: return nil
        }
    }

    /// A hash cut to 16 bytes and kept in a UUID: tens of thousands of these cost far less memory than as many strings.
    private static func hash(_ text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return NSUUID(uuidBytes: bytes) as UUID
    }

    /// Which items to hold in memory: the newest `limit` unpinned ones and every pin, plus anything retention is about to expire
    /// so it can be archived. A nil limit means all of them.
    static func selection(_ records: [ClipRecord], limit: Int?, cutoff: Date?) -> Set<UUID> {
        guard let limit else { return Set(records.map(\.id)) }
        let newest = records.filter { !$0.pinned }.sorted { $0.date > $1.date }.prefix(limit)
        let mustHave = records.filter { record in record.pinned || cutoff.map { record.touched < $0 } == true }
        return Set(newest.map(\.id)).union(mustHave.map(\.id))
    }
}

/// The items on disk that are not in memory. Their counts and identities stand in for them until they are loaded.
struct DeferredHistory {
    typealias App = (name: String, bundle: String?, count: Int)

    private(set) var count = 0
    private(set) var apps: [String: App] = [:]
    /// When the next of these items passes the retention period.
    private(set) var expiry: Date?
    /// Only what a repeat copy needs. The app key shares the string in `apps` rather than holding a copy of it.
    private var byIdentity: [UUID: Copy] = [:]

    struct Copy {
        var id: UUID
        var date: Date
        fileprivate var appKey: String?
    }

    var isEmpty: Bool { count == 0 }

    mutating func add(_ record: ClipRecord, lifetime: TimeInterval?) {
        count += 1
        var appKey: String?
        if let key = record.bundle ?? record.app {
            var app = apps[key] ?? (record.app ?? key, record.bundle, 0)
            app.count += 1
            apps[key] = app
            appKey = apps.index(forKey: key).map { apps.keys[$0] }
        }
        if let identity = record.identity { byIdentity[identity] = Copy(id: record.id, date: record.date, appKey: appKey) }
        if let lifetime {
            let expires = record.touched.addingTimeInterval(lifetime)
            expiry = min(expiry ?? expires, expires)
        }
    }

    /// Takes out the item with this identity, when it has been copied again, and returns it.
    mutating func take(identity: UUID) -> Copy? {
        guard let copy = byIdentity.removeValue(forKey: identity) else { return nil }
        count -= 1
        if let key = copy.appKey, var app = apps[key] {
            app.count -= 1
            apps[key] = app.count > 0 ? app : nil
        }
        return copy
    }
}

/// A cache of every month file's records, so a launch only reads the files it needs. It holds no clipboard text, stays on this
/// Mac, and can be deleted at any time: a changed or missing month is simply read again.
struct ClipboardIndex: Codable {
    private struct Entry: Codable {
        var signature: String
        var records: [ClipRecord]
    }

    private var version = Self.currentVersion
    private var files: [String: Entry] = [:]
    private var changed = false

    private enum CodingKeys: String, CodingKey { case version, files }
    // 2: text identity uses `Clip.contentKey`, so near-identical copies count as the same item.
    private static let currentVersion = 2
    private static var url: URL { supportDir.appendingPathComponent("clipboard-index.json") }

    var fileCount: Int { files.count }

    static func load() -> ClipboardIndex {
        guard let data = try? Data(contentsOf: url), let index = try? JSONDecoder().decode(ClipboardIndex.self, from: data),
              index.version == currentVersion else { return ClipboardIndex() }
        return index
    }

    func saveIfChanged() {
        guard changed, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    static func erase() { try? FileManager.default.removeItem(at: url) }

    mutating func records(in file: URL) -> [ClipRecord] {
        let signature = ClipboardFolder.fileSignature(file)
        let key = file.standardizedFileURL.path
        if let hit = files[key], hit.signature == signature { return hit.records }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let records = ClipHistoryFile.parse(text).map(ClipRecord.init)
        // Changed while it was being read: use what was read, but do not remember it for that version of the file.
        if signature == ClipboardFolder.fileSignature(file) {
            files[key] = Entry(signature: signature, records: records)
            changed = true
        }
        return records
    }

    /// Forgets files that no longer exist.
    mutating func keep(only urls: [URL]) {
        let keys = Set(urls.map(\.standardizedFileURL.path))
        guard !Set(files.keys).isSubset(of: keys) else { return }
        files = files.filter { keys.contains($0.key) }
        changed = true
    }
}
