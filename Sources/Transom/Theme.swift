import SwiftUI
import AppKit

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass on macOS 26 and later (when enabled), a blurred material elsewhere.
    @ViewBuilder func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, enabled: Bool = true) -> some View {
        if enabled, Env["NOGLASS"] == nil, #available(macOS 26.0, *) {
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
    /// The line between sidebar and page. Opaque on purpose: a translucent line over the window's own backdrop shows
    /// as a bright bar in dark mode.
    static let divider = dynamic(light: NSColor(white: 0.88, alpha: 1), dark: NSColor(white: 0.21, alpha: 1))
    static let selection = Color.primary.opacity(0.075)

    static let pageTitle = Font.system(size: 26, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 14)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let meta = Font.system(size: 12)
    static let overline = Font.system(size: 11, weight: .semibold)

    static let cardRadius: CGFloat = 16
    /// One height for every control in a page header (search, Select, chips), so they line up.
    static let controlHeight: CGFloat = 34
    /// Space between a page heading (title, subtitle, chips) and the content under it, the same on every page.
    static let headerGap: CGFloat = 26
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
        .padding(.horizontal, 14).frame(height: Look.controlHeight)
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
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            Text(title).font(.system(size: 14, weight: selected ? .semibold : .regular))
            Spacer()
            if let trailing { Text(trailing).font(Look.meta).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Look.selection : (hovering.value ? Look.selection.opacity(0.55) : .clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
    }
}

/// A small group title in a sidebar ("Clipboard", "Saved"), quiet so the rows carry the weight.
struct SidebarHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 6)
    }
}

struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
            Text("Transom").font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.top, 40).padding(.bottom, 16)
    }
}

/// Page title with Craft's round "+" button beside it.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var plus: (() -> Void)?
    /// Pages with their own toolbar row put the search field there instead.
    var showsSearch = true
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
            HStack(spacing: 10) {
                trailing()
                if showsSearch { SearchBarButton() }
            }
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
    /// A window: a glass top pane (the transom) over a bar, with three small items below. Drawn as a template so macOS tints it
    /// for light and dark bars; the pane is a lighter tone of the same tint.
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            // Top-down coordinates (the image is flipped).
            let frame = NSRect(x: 2, y: 1.5, width: 16, height: 13)
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.4
            // The pane: a lighter fill under the frame's top.
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSColor.black.withAlphaComponent(0.38).setFill()
            NSRect(x: 2, y: 1.5, width: 16, height: 4.9).fill()
            NSGraphicsContext.restoreGraphicsState()
            outline.stroke()
            // The transom bar.
            NSColor.black.setFill()
            NSRect(x: 2.4, y: 5.9, width: 15.2, height: 1.5).fill()
            // Page, picture and link.
            NSBezierPath(roundedRect: NSRect(x: 4.4, y: 9, width: 2.8, height: 3.6), xRadius: 0.7, yRadius: 0.7).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.6, y: 9, width: 2.8, height: 3.0), xRadius: 0.7, yRadius: 0.7).fill()
            NSBezierPath(roundedRect: NSRect(x: 12.8, y: 9, width: 2.8, height: 2.8), xRadius: 1.0, yRadius: 1.0).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
