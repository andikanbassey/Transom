import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
// The last few things the clipboard watcher saw and what it did with them.

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
