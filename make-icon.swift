// Renders the app icon set (needs only the Command Line Tools): a glass-look drawer holding a page of text, a picture
// and a link, on a rounded tile. Run by build.sh when the .icns is missing.
//   swift make-icon.swift AppIcon          release: slate tile
//   swift make-icon.swift AppIcon-beta beta   Beta: amber tile, same drawing
// Colours and shapes are in BRANDING.md; change them there and here together.
import AppKit

let out = CommandLine.arguments[1]
let beta = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "beta"
let iconset = out + ".iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let S: CGFloat = 1024
/// A rect given from the top-left of the 1024 x 1024 drawing, as AppKit wants it (origin bottom-left).
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: S - y - h, width: w, height: h) }
func rounded(_ r: NSRect, _ radius: CGFloat, _ fill: NSColor) { fill.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }

func tilted(_ rect: NSRect, _ deg: CGFloat, _ body: () -> Void) {
    let t = NSAffineTransform()
    t.translateX(by: rect.midX, yBy: rect.midY); t.rotate(byDegrees: deg); t.translateX(by: -rect.midX, yBy: -rect.midY)
    NSGraphicsContext.saveGraphicsState(); t.concat(); body(); NSGraphicsContext.restoreGraphicsState()
}

func shadowed(_ blur: CGFloat, _ alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowOffset = NSSize(width: 0, height: -10); s.shadowBlurRadius = blur
    s.shadowColor = NSColor(white: 0, alpha: alpha); s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

/// The drawing, in the 1024 space, centred in the tile.
func drawDrawer() {
    let interior = beta ? NSColor(red: 0.28, green: 0.14, blue: 0.04, alpha: 1) : NSColor(red: 0.09, green: 0.10, blue: 0.16, alpha: 1)
    rounded(R(236, 212, 552, 300), 52, interior)

    // A page of text.
    shadowed(22, 0.28) {
        let r = R(222, 150, 226, 322)
        tilted(r, 6) {
            rounded(r, 24, .white)
            NSColor(white: 0.62, alpha: 1).setFill()
            for (i, w) in [160, 160, 160, 100].enumerated() {
                NSBezierPath(roundedRect: R(248, 190 + CGFloat(i) * 42, CGFloat(w), 16), xRadius: 8, yRadius: 8).fill()
            }
            NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: R(248, 370, 70, 16), xRadius: 8, yRadius: 8).fill()
        }
    }
    // A picture: sky, sun and hills.
    shadowed(22, 0.28) {
        let r = R(392, 168, 270, 262)
        tilted(r, -4) {
            let card = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
            NSGraphicsContext.saveGraphicsState(); card.addClip()
            NSGradient(colors: [NSColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1), NSColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1)])!
                .draw(in: r, angle: -90)
            NSColor.white.setFill(); NSBezierPath(ovalIn: R(572, 200, 56, 56)).fill()
            NSColor(red: 0.20, green: 0.55, blue: 0.40, alpha: 1).setFill()
            let hill = NSBezierPath()
            hill.move(to: NSPoint(x: 392, y: S - 430)); hill.line(to: NSPoint(x: 392, y: S - 350))
            hill.curve(to: NSPoint(x: 520, y: S - 322), controlPoint1: NSPoint(x: 430, y: S - 330), controlPoint2: NSPoint(x: 480, y: S - 300))
            hill.curve(to: NSPoint(x: 662, y: S - 372), controlPoint1: NSPoint(x: 570, y: S - 345), controlPoint2: NSPoint(x: 620, y: S - 340))
            hill.line(to: NSPoint(x: 662, y: S - 430)); hill.close(); hill.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    // Something else: a link.
    shadowed(22, 0.28) {
        let r = R(648, 228, 140, 140)
        tilted(r, 9) {
            rounded(r, 36, NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1))
            let cfg = NSImage.SymbolConfiguration(pointSize: 76, weight: .bold).applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let g = sym.size
                sym.draw(in: NSRect(x: r.midX - g.width / 2, y: r.midY - g.height / 2, width: g.width, height: g.height))
            }
        }
    }
    // The drawer front: frosted, lighter at the top, with its pull.
    shadowed(34, 0.35) {
        let r = R(186, 420, 652, 424)
        let p = NSBezierPath(roundedRect: r, xRadius: 84, yRadius: 84)
        NSGradient(colors: [NSColor.white, NSColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1)])!.draw(in: p, angle: -90)
    }
    NSColor(white: 1, alpha: 0.9).setStroke()
    let rim = NSBezierPath(roundedRect: R(188, 422, 648, 420), xRadius: 82, yRadius: 82); rim.lineWidth = 3; rim.stroke()
    NSColor(white: 0, alpha: 0.18).setFill()
    NSBezierPath(roundedRect: R(392, 580, 240, 52), xRadius: 26, yRadius: 26).fill()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / S
    let scale = NSAffineTransform(); scale.scale(by: k); scale.concat()
    // Tile: 824 of 1024, centred, with a soft shadow.
    let tile = R(100, 100, 824, 824)
    let top = beta ? NSColor(red: 1.00, green: 0.72, blue: 0.20, alpha: 1) : NSColor(red: 0.227, green: 0.255, blue: 0.337, alpha: 1)
    let bottom = beta ? NSColor(red: 0.94, green: 0.42, blue: 0.10, alpha: 1) : NSColor(red: 0.071, green: 0.078, blue: 0.122, alpha: 1)
    shadowed(24, 0.30) {
        NSGradient(colors: [top, bottom])!.draw(in: NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185), angle: -90)
    }
    // Content: scaled to sit inside the tile, nudged to its optical centre.
    let t = NSAffineTransform()
    t.translateX(by: 512, yBy: 512 - 14); t.scale(by: 0.84); t.translateX(by: -512, yBy: -512)
    t.concat()
    drawDrawer()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
    }
}
