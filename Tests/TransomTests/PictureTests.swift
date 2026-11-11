import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Transom

/// Pictures are judged by their bytes: some apps put JPEG data on the pasteboard as PNG, and older versions saved it
/// under a .png name, which made QuickLook show a generic PNG icon instead of the picture.
@Suite struct PictureTests {
    private func jpeg(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .jpeg, properties: [:])!
    }

    @Test func typeComesFromTheBytes() {
        #expect(Thumbs.pictureType(of: jpeg(width: 40, height: 30)) == .jpeg)
        #expect(Thumbs.pictureType(of: Data("not a picture".utf8)) == nil)
    }

    @Test func jpegNamedPNGStillGetsAThumbnail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try jpeg(width: 3274, height: 2232).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Thumbs.pictureType(at: url) == .jpeg)
        let thumb = try #require(Thumbs.pictureThumbnail(url, size: CGSize(width: 196, height: 150), scale: 2))
        // Scaled down to fill the card at 2x, not the full 3274 pixels.
        #expect(thumb.size.height >= 150 && thumb.size.width < 1000)
    }

    @Test func notAPictureFallsBackToQuickLook() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Thumbs.pictureThumbnail(url, size: CGSize(width: 50, height: 50), scale: 2) == nil)
    }
}
