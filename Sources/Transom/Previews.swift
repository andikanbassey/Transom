import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
// Cover art and icons: picture and file thumbnails, link previews and the icons of the apps items came from.

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
        // Pictures kept on this Mac that no item refers to (left by a failed delete) are removed too.
        let pictures = Set(clips.compactMap(\.imageFile))
        for name in (try? fm.contentsOfDirectory(atPath: ClipboardFolder.localImages.path)) ?? [] where !pictures.contains(name) && !name.hasPrefix(".") {
            try? fm.removeItem(at: ClipboardFolder.localImages.appendingPathComponent(name))
        }
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
