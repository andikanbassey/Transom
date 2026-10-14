import SwiftUI
import AppKit

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass on macOS 26 and later (when enabled), a blurred material elsewhere.
    @ViewBuilder func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, enabled: Bool = true) -> some View {
        if enabled, ProcessInfo.processInfo.environment["DRAWER_NOGLASS"] == nil, #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(tint ?? .clear, in: shape)
        }
    }
}

// MARK: - Contrast and size

enum Contrast {
    /// With Liquid Glass and a very low background opacity the wallpaper shows through, so chips become solid colour
    /// with white content instead of tinted text on a faint tint.
    static var solidChips: Bool {
        let v = Settings.shared.v
        return v.liquidGlass && v.translucency < 0.5
    }
}

enum UIScale {
    /// Base type scale for the drawer. A user-facing size setting can drive this later.
    static var value: CGFloat = 1.15
}
func fs(_ size: CGFloat) -> CGFloat { size * UIScale.value }

// MARK: - Shared look (Library, Settings and search)

/// One set of colours, type and shapes so the Library and Settings read as two sides of the same app.
enum Look {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let page = dynamic(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.105, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 0.168, alpha: 1))
    static let sidebar = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.135, alpha: 1))
    static let hairline = Color.primary.opacity(0.08)
    static let selection = Color.primary.opacity(0.075)

    static let pageTitle = Font.system(size: 26, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 14)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let meta = Font.system(size: 12)
    static let overline = Font.system(size: 11, weight: .semibold)

    static let cardRadius: CGFloat = 16
    static let sidebarWidth: CGFloat = 230
}

extension View {
    /// The soft white card used for panels and settings groups.
    func lookCard(radius: CGFloat = Look.cardRadius, shadow: Bool = true) -> some View {
        self.background(Look.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(shadow ? 0.07 : 0), radius: 8, y: 2)
    }
}

/// A rounded-rectangle chip. Selected chips are light accent with accent text, as in Craft.
struct Chip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering.value ? 0.09 : 0.055),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture(perform: action)
    }
}

/// One row in a window sidebar: a small coloured tile, a label, and an optional count.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    var trailing: String?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            Text(title).font(.system(size: 14, weight: selected ? .semibold : .regular))
            Spacer()
            if let trailing { Text(trailing).font(Look.meta).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(selected ? Look.selection : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
            Text(isBeta ? "Drawer Beta" : "Drawer").font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.top, 40).padding(.bottom, 16)
    }
}

/// Page title with Craft's round "+" button beside it.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var plus: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let plus {
                Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
                    .background(Look.card, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                    .contentShape(Circle())
                    .onTapGesture(perform: plus)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Look.pageTitle)
                if let subtitle { Text(subtitle).font(Look.body).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing()
            SearchBarButton()
        }
        .zIndex(10)
    }
}

// MARK: - Controls

/// Secondary button used inside settings rows.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, prominent: prominent) }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @StateObject private var hovering = Box(false)
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(
                    Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(hovering.value ? 0.14 : 0.09))
                )
                .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : 0.06), lineWidth: 1))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .onHover { hovering.value = $0 }
        }
    }
}

// MARK: - Menu bar icon

enum MenuBarIcon {
    /// A screen edge with a drawer pulled down from it. Drawn as a template so macOS tints it for light and dark bars.
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 16, height: 13), xRadius: 3.6, yRadius: 3.6)
            frame.lineWidth = 1.4
            frame.stroke()
            let drawer = NSBezierPath(roundedRect: NSRect(x: 4.6, y: 6.2, width: 10.8, height: 5.6), xRadius: 1.8, yRadius: 1.8)
            drawer.fill()
            let handle = NSBezierPath(roundedRect: NSRect(x: 8, y: 4.1, width: 4, height: 1.3), xRadius: 0.65, yRadius: 0.65)
            handle.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
