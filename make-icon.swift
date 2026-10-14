// Renders an app icon set: a rounded square with a tray glyph. Run by build.sh when the icon is missing.
//   swift make-icon.swift AppIcon          release: dark slate tile
//   swift make-icon.swift AppIcon-beta beta   beta: amber tile with a β badge
// Colours and sizes are in BRANDING.md; change them there and here together.
import AppKit

let out = CommandLine.arguments[1]
let beta = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "beta"
let iconset = out + ".iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    let tile = beta
        ? [NSColor(red: 1.00, green: 0.72, blue: 0.20, alpha: 1), NSColor(red: 0.94, green: 0.42, blue: 0.10, alpha: 1)]
        : [NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1), NSColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)]
    NSGradient(colors: tile)!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let g = sym.size
        sym.draw(in: NSRect(x: (s - g.width) / 2, y: (s - g.height) / 2, width: g.width, height: g.height))
    }
    if beta, px >= 64 {
        // A dark disc with a white β in the lower right corner: still readable when the icon is small.
        let d = s * 0.30
        let disc = NSRect(x: s * 0.94 - d - s * 0.02, y: s * 0.06 + s * 0.02, width: d, height: d)
        NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(ovalIn: disc).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: disc.insetBy(dx: s * 0.008, dy: s * 0.008)); ring.lineWidth = s * 0.012; ring.stroke()
        let str = NSAttributedString(string: "β", attributes: [.font: NSFont.systemFont(ofSize: d * 0.62, weight: .bold), .foregroundColor: NSColor.white])
        let sz = str.size()
        str.draw(at: NSPoint(x: disc.midX - sz.width / 2, y: disc.midY - sz.height / 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
    }
}
