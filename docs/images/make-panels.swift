// Cuts the three panels (Quick Access, Clipboard, Notes) out of docs/images/drawer.png for the README, with rounded corners.
//   swift docs/images/make-panels.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let source = NSBitmapImageRep(data: try! Data(contentsOf: root.appendingPathComponent("drawer.png")))!
// Pixel rectangles in the 3840 x 600 render (the drawer is 1920 pt wide at 2x). Quick Access and Notes share one size so they sit evenly side by side in the README table.
// The last number is extra margin added to the left and right, filled with the panel's own colour, so content never sits
// close to the picture's edge (the Notes panel runs right up to the edge of the screen in the render).
// The README shows the Clipboard panel full width, so it takes the whole panel.
// The fourth number is where, across the crop, to take the empty patch the margin colour is copied from.
let panels: [(String, CGRect, CGFloat, CGFloat)] = [
    ("drawer-quick-access.png", CGRect(x: 6, y: 0, width: 760, height: 460), 28, 380),
    ("drawer-clipboard.png", CGRect(x: 790, y: 0, width: 2270, height: 600), 28, 6),
    ("drawer-notes.png", CGRect(x: 3072, y: 0, width: 760, height: 460), 28, 380),
]
for (name, r, pad, patchX) in panels {
    let w = Int(r.width + 2 * pad), h = Int(r.height)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let full = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh)); full.addRepresentation(source)
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 40, yRadius: 40).addClip()
    // The panel's own colour, sampled from an empty spot near the bottom middle of the crop, fills the margin.
    // Draw the whole source offset so the wanted rectangle lands inside the margin (AppKit's y runs upward).
    if pad > 0 {
        // The margins are stretched from an empty patch of the panel itself (low in the crop, in the middle), so the colour matches
        // the panel exactly.
        let patch = NSRect(x: r.minX + patchX, y: CGFloat(source.pixelsHigh) - r.maxY + 6, width: 20, height: 10)
        full.draw(in: NSRect(x: 0, y: 0, width: pad, height: CGFloat(h)), from: patch, operation: .copy, fraction: 1)
        full.draw(in: NSRect(x: CGFloat(w) - pad, y: 0, width: pad, height: CGFloat(h)), from: patch, operation: .copy, fraction: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: pad, y: 0, width: r.width, height: r.height)).addClip()   // only the panel, not its neighbours
    full.draw(in: NSRect(x: pad - r.minX, y: -(CGFloat(source.pixelsHigh) - r.maxY), width: CGFloat(source.pixelsWide), height: CGFloat(source.pixelsHigh)))
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try! out.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
}
print("done")
