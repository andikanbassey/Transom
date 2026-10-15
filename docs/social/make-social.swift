// Draws the picture cards for announcing Drawer: X, LinkedIn and WhatsApp (square and status). Command Line Tools only.
//   swift docs/social/make-social.swift
// Reads docs/images/drawer.png, docs/images/onboarding-2.png and AppIcon.icns; writes the PNGs next to this script.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("docs/social")
let drawer = NSImage(contentsOf: root.appendingPathComponent("docs/images/drawer.png"))!
let welcome = NSImage(contentsOf: root.appendingPathComponent("docs/images/onboarding-2.png"))!
let icon = NSImage(contentsOf: root.appendingPathComponent("AppIcon.icns"))!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// One card: `body` draws with a top-left origin in a w x h canvas (y grows downward).
func card(_ name: String, _ w: Int, _ h: Int, body: (CGFloat, CGFloat) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let base = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Flip so the origin is top-left.
    base.translateBy(x: 0, y: CGFloat(h)); base.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: base, flipped: true)
    let W = CGFloat(w), H = CGFloat(h)
    NSGradient(colors: [color(0x0D1020), color(0x2A3150)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -50)
    for (c, x, y, r) in [(color(0x4F7BFF, 0.40), W * 0.92, H * 0.05, W * 0.55), (color(0x8B5CF6, 0.30), W * 0.05, H * 0.95, W * 0.5),
                         (color(0xFF8A4C, 0.20), W * 0.55, H * 1.05, W * 0.45)] {
        NSGradient(colors: [c, c.withAlphaComponent(0)])!.draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }
    body(W, H)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

func text(_ s: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color c: NSColor = .white, line: CGFloat = 1.12, align: NSTextAlignment = .left) -> CGFloat {
    let p = NSMutableParagraphStyle(); p.lineHeightMultiple = line; p.alignment = align
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c, .paragraphStyle: p])
    let r = a.boundingRect(with: NSSize(width: width, height: 4000), options: [.usesLineFragmentOrigin])
    a.draw(with: NSRect(x: x, y: y, width: width, height: r.height), options: [.usesLineFragmentOrigin])
    return ceil(r.height)
}

func picture(_ img: NSImage, in rect: NSRect, from src: NSRect? = nil, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowOffset = NSSize(width: 0, height: 18); s.shadowBlurRadius = 40; s.shadowColor = NSColor(white: 0, alpha: 0.5); s.set()
    NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    // The image is drawn upright inside the flipped canvas.
    img.draw(in: rect, from: src ?? .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.14).setStroke()
    let b = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius); b.lineWidth = 1.5; b.stroke()
}

func brand(x: CGFloat, y: CGFloat, size: CGFloat) {
    icon.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    _ = text("Drawer", x: x + size * 1.18, y: y + size * 0.22, width: 600, size: size * 0.5, weight: .bold)
}

func pill(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: .semibold)
    let w = (s as NSString).size(withAttributes: [.font: font]).width + size * 1.6
    let r = NSRect(x: x, y: y, width: w, height: size * 2.1)
    color(0xFFFFFF, 0.10).setFill(); NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    color(0xFFFFFF, 0.16).setStroke(); NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: r.height / 2, yRadius: r.height / 2).stroke()
    _ = text(s, x: x + size * 0.8, y: y + size * 0.52, width: w, size: size, weight: .semibold, color: color(0xFFFFFF, 0.92))
    return w
}

let cards = NSRect(x: 0, y: 0, width: 1300, height: 300)     // the left part of the drawer picture
let aspect: CGFloat = 1300 / 300
let headline = "Your clipboard,\none scroll away."
let sub = "Clipboard history, notes and pinned files in a drawer at the top of your Mac."

card("x-1600x900.png", 1600, 900) { W, H in
    brand(x: 80, y: 60, size: 72)
    var y: CGFloat = 170
    y += text(headline, x: 80, y: y, width: 1440, size: 84, weight: .bold, line: 1.0) + 20
    _ = text(sub, x: 80, y: y, width: 1440, size: 30, color: color(0xFFFFFF, 0.72), line: 1.2)
    picture(drawer, in: NSRect(x: 80, y: 470, width: W - 160, height: (W - 160) / aspect), from: cards, radius: 28)
    _ = pill("Free and open source", x: 80, y: 842, size: 20)
}

card("linkedin-1200x627.png", 1200, 627) { W, H in
    brand(x: 60, y: 40, size: 52)
    var y: CGFloat = 112
    y += text(headline, x: 60, y: y, width: 1080, size: 58, weight: .bold, line: 1.0) + 12
    _ = text(sub, x: 60, y: y, width: 1080, size: 22, color: color(0xFFFFFF, 0.72), line: 1.2)
    picture(drawer, in: NSRect(x: 60, y: 340, width: W - 120, height: (W - 120) / aspect), from: cards, radius: 22)
}

card("whatsapp-square-1080x1080.png", 1080, 1080) { W, H in
    brand(x: 70, y: 70, size: 76)
    var y: CGFloat = 190
    y += text(headline, x: 70, y: y, width: 940, size: 86, weight: .bold, line: 1.0) + 20
    _ = text(sub, x: 70, y: y, width: 900, size: 30, color: color(0xFFFFFF, 0.72), line: 1.2)
    picture(drawer, in: NSRect(x: 70, y: 540, width: W - 140, height: (W - 140) / aspect), from: cards, radius: 24)
    var px: CGFloat = 70, py: CGFloat = 790
    for item in ["Filter by time, type and app", "Drag items into notes", "Select and delete in bulk", "Syncs through iCloud Drive"] {
        let w = pill(item, x: px, y: py, size: 25)
        px += w + 14
        if px > W - 330 { px = 70; py += 74 }
    }
}

card("whatsapp-status-1080x1920.png", 1080, 1920) { W, H in
    brand(x: 90, y: 120, size: 88)
    var y: CGFloat = 270
    y += text(headline, x: 90, y: y, width: 920, size: 100, weight: .bold, line: 1.0) + 24
    _ = text(sub, x: 90, y: y, width: 880, size: 36, color: color(0xFFFFFF, 0.72), line: 1.2)
    let pw: CGFloat = 700, ph = pw * 923 / 760
    picture(welcome, in: NSRect(x: (W - pw) / 2, y: 720, width: pw, height: ph), radius: 36)
    _ = pill("Free and open source  ·  macOS 14+", x: 90, y: 1790, size: 28)
}
print("done")
