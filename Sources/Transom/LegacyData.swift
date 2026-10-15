import AppKit

/// The app was called Drawer until 0.7. Its data folder moves to the new name the first time Transom starts, before anything
/// reads it, so history, notes and settings come across unchanged.
enum LegacyData {
    static let noticeKey = "renameNoticePending"

    /// Moves `Application Support/Drawer` to `url` (`.../Transom`) when only the old one exists. Returns the folder to use:
    /// the old one if the move failed, so nothing is ever lost or started empty.
    static func moveIfNeeded(base: URL, into url: URL) -> URL {
        let fm = FileManager.default
        let old = base.appendingPathComponent("Drawer", isDirectory: true)
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: old.path) else { return url }
        do {
            try fm.moveItem(at: old, to: url)
        } catch {
            return old
        }
        // Settings may hold folders inside the old path (written plain or with escaped slashes by the JSON encoder).
        let settings = url.appendingPathComponent("settings.json")
        if var text = try? String(contentsOf: settings, encoding: .utf8) {
            for (a, b) in [("Application Support/Drawer", "Application Support/Transom"),
                           ("Application Support\\/Drawer", "Application Support\\/Transom")] {
                text = text.replacingOccurrences(of: a, with: b)
            }
            try? text.write(to: settings, atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(true, forKey: noticeKey)
        return url
    }

    /// Says once, after a move, that the app has a new name. Does nothing on any other launch.
    static func showNoticeIfNeeded() {
        guard UserDefaults.standard.bool(forKey: noticeKey) else { return }
        UserDefaults.standard.set(false, forKey: noticeKey)
        let alert = NSAlert()
        alert.messageText = "Drawer is now \(Brand.name)"
        alert.informativeText = "Your history and notes are unchanged. The shortcut, settings and Accessibility permission carry over."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
