// Renders the app icon set (needs only the Command Line Tools): a window with a glass top pane (the transom), a bar under it,
// and a page of text, a picture and a link below, on a rounded tile. Run by build.sh when the .icns is missing.
//   swift make-icon.swift AppIcon
// Colours and shapes are in BRANDING.md; change them there and here together.
import AppKit

let out = CommandLine.arguments[1]
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

/// Sketch units (a 200 x 200 tile whose rounded square runs 18 to 182) to the 1024 drawing.
let k: CGFloat = 824 / 164
func U(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { R(100 + (x - 18) * k, 100 + (y - 18) * k, w * k, h * k) }

/// A window seen from the front: a glass top pane (the transom), a bar under it, and the three kinds of item below.
func drawTransom() {
    let blue = NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
    let frame = U(46, 44, 108, 112)
    let radius = 14 * k
    // The room behind the window.
    rounded(frame, radius, NSColor(red: 0.09, green: 0.10, blue: 0.16, alpha: 1))
    // A little light falling from the pane into the room.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    NSGradient(colors: [NSColor(red: 0.56, green: 0.71, blue: 1.0, alpha: 0.40), NSColor(red: 0.56, green: 0.71, blue: 1.0, alpha: 0)])!
        .draw(in: U(46, 78, 108, 70), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Items under the bar.
    shadowed(18, 0.30) {
        let page = U(60, 92, 26, 50)
        tilted(page, -3) {
            rounded(page, 5 * k, .white)
            NSColor(white: 0.62, alpha: 1).setFill()
            for (i, w) in [17, 17, 17, 10].enumerated() {
                NSBezierPath(roundedRect: U(64, 98 + CGFloat(i) * 6.6, CGFloat(w), 2.6), xRadius: 1.3 * k, yRadius: 1.3 * k).fill()
            }
            blue.setFill(); NSBezierPath(roundedRect: U(64, 125, 9, 2.6), xRadius: 1.3 * k, yRadius: 1.3 * k).fill()
        }
        let pic = U(92, 92, 26, 40)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: pic, xRadius: 5 * k, yRadius: 5 * k).addClip()
        NSGradient(colors: [NSColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1), NSColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1)])!.draw(in: pic, angle: -90)
        NSColor.white.setFill(); NSBezierPath(ovalIn: U(106, 96, 8, 8)).fill()
        NSColor(red: 0.20, green: 0.55, blue: 0.40, alpha: 1).setFill()
        let hill = NSBezierPath()
        let p0 = U(92, 132, 0, 0).origin, p1 = U(92, 122, 0, 0).origin
        hill.move(to: p0); hill.line(to: p1)
        hill.curve(to: U(106, 116, 0, 0).origin, controlPoint1: U(96, 120, 0, 0).origin, controlPoint2: U(101, 114, 0, 0).origin)
        hill.curve(to: U(118, 122, 0, 0).origin, controlPoint1: U(111, 118, 0, 0).origin, controlPoint2: U(115, 118, 0, 0).origin)
        hill.line(to: U(118, 132, 0, 0).origin); hill.close(); hill.fill()
        NSGraphicsContext.restoreGraphicsState()
        let link = U(124, 102, 20, 20)
        tilted(link, 6) {
            rounded(link, 6 * k, blue)
            let cfg = NSImage.SymbolConfiguration(pointSize: 14 * k, weight: .bold).applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let g = sym.size
                sym.draw(in: NSRect(x: link.midX - g.width / 2, y: link.midY - g.height / 2, width: g.width, height: g.height))
            }
        }
    }

    // The glass top pane (the transom), and the bar under it. The pane is drawn taller and cut off at the bar, so only its
    // top corners are round.
    let cut = U(46, 44, 108, 26)
    shadowed(24, 0.28) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cut.insetBy(dx: -40, dy: 0).offsetBy(dx: 0, dy: 0)).addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.97), NSColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 0.9)])!
            .draw(in: NSBezierPath(roundedRect: U(46, 44, 108, 60), xRadius: radius, yRadius: radius), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(rect: U(46, 70, 108, 8)).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: cut).addClip()
    NSColor(white: 1, alpha: 0.9).setStroke()
    let rim = NSBezierPath(roundedRect: U(46.5, 44.5, 107, 59), xRadius: radius - 0.5 * k, yRadius: radius - 0.5 * k); rim.lineWidth = 3; rim.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: 0.22).setStroke()
    let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1.5, dy: 1.5), xRadius: radius, yRadius: radius); outline.lineWidth = 3; outline.stroke()
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
    let top = NSColor(red: 0.227, green: 0.255, blue: 0.337, alpha: 1)
    let bottom = NSColor(red: 0.071, green: 0.078, blue: 0.122, alpha: 1)
    shadowed(24, 0.30) {
        NSGradient(colors: [top, bottom])!.draw(in: NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185), angle: -90)
    }
    drawTransom()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
    }
}
