// Cuts the three panels (Quick Access, Clipboard, Notes) out of docs/images/drawer.png for the README, with rounded corners.
//   swift docs/images/make-panels.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let source = NSBitmapImageRep(data: try! Data(contentsOf: root.appendingPathComponent("drawer.png")))!
// Pixel rectangles in the 3840 x 600 render (the drawer is 1920 pt wide at 2x).
let panels: [(String, CGRect)] = [
    ("drawer-quick-access.png", CGRect(x: 0, y: 0, width: 778, height: 600)),
    ("drawer-clipboard.png", CGRect(x: 790, y: 0, width: 1500, height: 600)),
    ("drawer-notes.png", CGRect(x: 3100, y: 0, width: 740, height: 600)),
]
for (name, r) in panels {
    let w = Int(r.width), h = Int(r.height)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 40, yRadius: 40).addClip()
    // Draw the whole source offset so the wanted rectangle lands at the origin (AppKit's y runs upward).
    let full = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh)); full.addRepresentation(source)
    full.draw(in: NSRect(x: -r.minX, y: -(CGFloat(source.pixelsHigh) - r.maxY), width: CGFloat(source.pixelsWide), height: CGFloat(source.pixelsHigh)))
    NSGraphicsContext.restoreGraphicsState()
    try! out.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
}
print("done")
