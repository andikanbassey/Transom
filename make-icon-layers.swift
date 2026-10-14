// Draws the layer artwork for the Icon Composer icons (Resources/AppIcon.icon and AppIconBeta.icon).
// Each layer is a 1024 x 1024 transparent PNG; Icon Composer adds the tile, glass, shadow and light/dark looks.
//   swift make-icon-layers.swift Resources
// Layers, back to front: interior, page, photo, link, front.
import AppKit

let out = CommandLine.arguments[1]
let S: CGFloat = 1024

func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: S - y - h, width: w, height: h) }

func layer(_ name: String, folder: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(folder)/Assets/\(name).png"))
}

/// Draws `body` rotated by `deg` around the centre of `rect`.
func tilted(_ rect: NSRect, _ deg: CGFloat, _ body: () -> Void) {
    let t = NSAffineTransform()
    t.translateX(by: rect.midX, yBy: rect.midY); t.rotate(byDegrees: deg); t.translateX(by: -rect.midX, yBy: -rect.midY)
    NSGraphicsContext.saveGraphicsState(); t.concat(); body(); NSGraphicsContext.restoreGraphicsState()
}
func rounded(_ r: NSRect, _ radius: CGFloat, fill: NSColor) { fill.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }

for (folder, interior) in [("AppIcon.icon", NSColor(red: 0.09, green: 0.10, blue: 0.16, alpha: 1)),
                           ("AppIconBeta.icon", NSColor(red: 0.28, green: 0.14, blue: 0.04, alpha: 1))] {
    layer("interior", folder: folder) {
        rounded(R(236, 212, 552, 300), 52, fill: interior)
    }
    // A page of text.
    layer("page", folder: folder) {
        let r = R(244, 146, 226, 322)
        tilted(r, 6) {
            rounded(r, 24, fill: .white)
            NSColor(white: 0.62, alpha: 1).setFill()
            for (i, w) in [160, 160, 160, 100].enumerated() {
                NSBezierPath(roundedRect: R(270, 186 + CGFloat(i) * 42, CGFloat(w), 16), xRadius: 8, yRadius: 8).fill()
            }
            NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: R(270, 366, 70, 16), xRadius: 8, yRadius: 8).fill()
        }
    }
    // A picture: sky, sun and hills.
    layer("photo", folder: folder) {
        let r = R(392, 168, 270, 262)
        tilted(r, -4) {
            let card = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
            NSGraphicsContext.saveGraphicsState(); card.addClip()
            NSGradient(colors: [NSColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1), NSColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1)])!
                .draw(in: r, angle: -90)
            NSColor.white.setFill(); NSBezierPath(ovalIn: R(572, 200, 56, 56)).fill()
            NSColor(red: 0.20, green: 0.55, blue: 0.40, alpha: 1).setFill()
            let hill = NSBezierPath()
            hill.move(to: NSPoint(x: 398, y: S - 428)); hill.line(to: NSPoint(x: 398, y: S - 350))
            hill.curve(to: NSPoint(x: 520, y: S - 322), controlPoint1: NSPoint(x: 430, y: S - 330), controlPoint2: NSPoint(x: 480, y: S - 300))
            hill.curve(to: NSPoint(x: 662, y: S - 372), controlPoint1: NSPoint(x: 570, y: S - 345), controlPoint2: NSPoint(x: 620, y: S - 340))
            hill.line(to: NSPoint(x: 662, y: S - 428)); hill.close(); hill.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    // Something else: a link.
    layer("link", folder: folder) {
        let r = R(648, 228, 140, 140)
        tilted(r, 9) {
            rounded(r, 36, fill: NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1))
            let cfg = NSImage.SymbolConfiguration(pointSize: 76, weight: .bold).applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let g = sym.size
                sym.draw(in: NSRect(x: r.midX - g.width / 2, y: r.midY - g.height / 2, width: g.width, height: g.height))
            }
        }
    }
    // The drawer front, with its pull.
    layer("front", folder: folder) {
        rounded(R(186, 420, 652, 424), 84, fill: .white)
        NSColor(white: 0, alpha: 0.20).setFill()
        NSBezierPath(roundedRect: R(392, 580, 240, 52), xRadius: 26, yRadius: 26).fill()
    }
}
