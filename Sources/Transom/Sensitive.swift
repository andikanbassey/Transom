import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
// Sensitive items: recognising secrets, and the masked look with its scramble, dissolve and countdown.

/// Text that is a secret even when the app that copied it did not say so: API keys, tokens and private keys.
enum SecretPatterns {
    private static let patterns: [NSRegularExpression] = [
        #"^(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}$"#, #"^github_pat_[A-Za-z0-9_]{40,}$"#,
        #"^sk-[A-Za-z0-9_\-]{20,}$"#, #"^AKIA[0-9A-Z]{16}$"#, #"^xox[abprs]-[A-Za-z0-9\-]{10,}$"#,
        #"^AIza[0-9A-Za-z_\-]{35}$"#, #"^[sr]k_(live|test)_[0-9A-Za-z]{16,}$"#,
        #"^eyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}$"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func looksSecret(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 10_000 else { return false }
        let range = NSRange(t.startIndex..., in: t)
        return patterns.contains { $0.firstMatch(in: t, range: range) != nil }
    }
}

/// How far a sensitive item has dissolved: 0 until its last half minute, then up to 1 as the countdown reaches zero.
enum SensitiveFade {
    static let window: TimeInterval = 30
    static func amount(expiry: Date?, now: Date) -> Double {
        guard let expiry else { return 0 }
        return min(max(1 - expiry.timeIntervalSince(now) / window, 0), 1)
    }
    /// A steady 0...1 number for a character position, so the same glyphs vanish first every time.
    static func order(_ i: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &+ 1) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29; x = x &* 0xBF58_476D_1CE4_E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}

/// A sensitive item's stand-in text: block and symbol characters, at rest a quiet pattern and while the pointer is over it a
/// scramble that keeps changing. It never shows the real text; copying or pasting the item still uses it.
/// In the last 30 seconds before the item is removed the characters drop away one by one and the rest fade.
struct SensitiveText: View {
    let length: Int
    var active = false
    var size: CGFloat = 13
    var expiry: Date?

    private static let rest: [Character] = Array("▒")
    private static let scramble: [Character] = Array("░▒▓█#%&@$*+=?/\\<>")

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 0.07 : 0.5)) { context in
            let tick = active ? Int(context.date.timeIntervalSinceReferenceDate * 14) : 0
            let fade = SensitiveFade.amount(expiry: expiry, now: context.date)
            Text(glyphs(tick, fade: fade))
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(active ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.7))
                .opacity(1 - 0.6 * fade)
        }
        .lineLimit(3)
        .accessibilityLabel("Sensitive item, hidden")
    }

    private func glyphs(_ tick: Int, fade: Double) -> String {
        let n = min(max(length, 8), 36)
        var seed = UInt64(truncatingIfNeeded: tick &* 2_654_435_761)
        return String((0..<n).map { i -> Character in
            if SensitiveFade.order(i) < fade { return " " }
            guard active else { return Self.rest[0] }
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Self.scramble[Int((seed >> 33) % UInt64(Self.scramble.count))]
        })
    }
}

/// The cover of a sensitive picture, file or link: a field of block characters where the picture was, scrambling while the
/// pointer is over it, and dissolving as the countdown ends. The real content is never drawn.
struct SensitiveCover: View {
    let clip: Clip
    var active = false

    private static let rest: [Character] = Array("░▒░░▒▒░▓░▒")
    private static let scramble: [Character] = Array("░▒▓█#%&@$*+=?/\\<>")

    var body: some View {
        GeometryReader { geo in
            let size = max(7, min(geo.size.width, geo.size.height) / 9)
            let cols = max(4, Int(geo.size.width / (size * 0.62)))
            let rows = max(2, Int(geo.size.height / (size * 1.25)))
            TimelineView(.animation(minimumInterval: active ? 0.07 : 0.5)) { context in
                let tick = active ? Int(context.date.timeIntervalSinceReferenceDate * 12) : 0
                let fade = SensitiveFade.amount(expiry: clip.sensitiveExpiry, now: context.date)
                ZStack {
                    Color.primary.opacity(0.06)
                    Text(field(cols: cols, rows: rows, tick: tick, fade: fade))
                        .font(.system(size: size, weight: .medium, design: .monospaced))
                        .foregroundStyle(active ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.55))
                        .lineSpacing(size * 0.1)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    Image(systemName: "lock.fill")
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.22, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .opacity(1 - fade)
                }
                .opacity(1 - 0.5 * fade)
            }
        }
        .accessibilityLabel(clip.sensitiveTitle + ", hidden")
    }

    private func field(cols: Int, rows: Int, tick: Int, fade: Double) -> String {
        var seed = UInt64(truncatingIfNeeded: tick &* 2_654_435_761) &+ 17
        var out = ""
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                if SensitiveFade.order(i) < fade { out.append(" "); continue }
                if active {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    out.append(Self.scramble[Int((seed >> 33) % UInt64(Self.scramble.count))])
                } else {
                    out.append(Self.rest[Int(SensitiveFade.order(i &* 7 &+ 3) * Double(Self.rest.count)) % Self.rest.count])
                }
            }
            if r < rows - 1 { out.append("\n") }
        }
        return out
    }
}

/// The countdown on a sensitive item: a ring that empties and the time left, which turns orange for the last half minute.
struct SensitiveClock: View {
    let expiry: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, expiry.timeIntervalSince(context.date))
            let ending = left <= SensitiveFade.window
            HStack(spacing: 4) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1.6)
                    Circle().trim(from: 0, to: left / ClipboardStore.sensitiveLifetime)
                        .stroke(ending ? Color.orange : Color.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 11, height: 11)
                Text(Self.format(left))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ending ? Color.orange : Color.secondary)
            }
            .help("This item is removed when the timer ends. It is kept in memory only.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Removed in \(Self.format(left))")
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
