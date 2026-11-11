import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

// Cover art and icons: picture and file thumbnails, link previews and the icons of the apps items came from.

enum Thumbs {
    private static let cache = NSCache<NSString, NSImage>()

    /// Cover art: pictures are read with ImageIO, which goes by the bytes, not the name; for anything else QuickLook gives the
    /// first frame of a video, the first page of a PDF, or the file icon.
    static func image(for url: URL, size: CGSize) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        // QuickLook picks its generator from the file name, so a JPEG saved as .png (some apps put JPEG bytes on the
        // pasteboard as PNG) came back as a generic PNG icon instead of the picture.
        if let picture = pictureThumbnail(url, size: size, scale: 2) {
            cache.setObject(picture, forKey: key)
            return picture
        }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .all)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return nil }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }

    /// What a picture's bytes really are (PNG, JPEG, HEIC…), whatever its name or pasteboard type says. Nil if it is not a picture.
    static func pictureType(of data: Data) -> UTType? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pictureType(src)
    }

    static func pictureType(at url: URL) -> UTType? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pictureType(src)
    }

    private static func pictureType(_ src: CGImageSource) -> UTType? {
        guard let id = CGImageSourceGetType(src) as String?, let type = UTType(id), type.conforms(to: .image) else { return nil }
        return type
    }

    /// A picture scaled down just enough to fill `size` at `scale`, read from the file's bytes. Nil for anything that is
    /// not a picture ImageIO can read, so the caller can fall back to QuickLook.
    static func pictureThumbnail(_ url: URL, size: CGSize, scale: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), pictureType(src) != nil,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        // Enough pixels for the shorter side to cover the frame (cards crop to fill), never more than the picture has.
        let fit = max(size.width / w, size.height / h) * scale
        let longest = min(max(w, h), max(64, (max(w, h) * fit).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
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
