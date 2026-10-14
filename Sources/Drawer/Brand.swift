import SwiftUI
import AppKit

/// What this build calls itself and how it marks itself, so the release app and the Beta can never be mixed up.
/// The values and their reasons are written down in BRANDING.md; change both together.
enum Brand {
    static var name: String { isBeta ? "Drawer Beta" : "Drawer" }
    static var channel: String { isBeta ? "Beta" : "Release" }
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.studioab.drawer" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    static let repoURL = URL(string: "https://github.com/andikanbassey/Drawer")!
    static var issuesURL: URL { repoURL.appendingPathComponent("issues") }
    static let copyright = "© 2026 Andikan Bassey"

    /// Amber marks the Beta everywhere (icon tile, sidebar pill). The release app stays neutral.
    static let betaAmber = Color(red: 0.96, green: 0.58, blue: 0.14)
    static let betaAmberDark = Color(red: 0.62, green: 0.30, blue: 0.04)
}

/// The small "BETA" pill that sits beside the name in the Beta build only.
struct BetaPill: View {
    var body: some View {
        if isBeta {
            Text("BETA").font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Brand.betaAmber, in: Capsule())
        }
    }
}
