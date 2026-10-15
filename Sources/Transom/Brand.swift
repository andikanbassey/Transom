import SwiftUI
import AppKit

/// What the app calls itself, in one place. The values and their reasons are written down in BRANDING.md.
enum Brand {
    static let name = "Transom"
    /// Kept from the Drawer days on purpose: changing it would reset the Accessibility grant, login item and preferences.
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.studioab.drawer" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    static let repoURL = URL(string: "https://github.com/andikanbassey/Transom")!
    static var issuesURL: URL { repoURL.appendingPathComponent("issues") }
    static let copyright = "© 2026 Andikan Bassey"
}
