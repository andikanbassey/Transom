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
    /// Between a page's heading row and its controls row (filters, Select, Search).
    static let toolbarGap: CGFloat = 18
    /// Items on one page of a Library list. Longer lists get a pagination bar under them.
    static let pageSize = Int(Env["PAGE_SIZE"] ?? "") ?? 48   // TRANSOM_PAGE_SIZE=4 makes the pagination bar easy to test
    /// The search field on every Library and Settings page.
    static let searchWidth: CGFloat = 260
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
        .accessibleTap(title, selected: selected, action)
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

/// The header of every Library and Settings page, so the same controls always sit in the same place:
///
///     [+]  Title                                  <- row 1: the primary action (if any) and the heading
///     filters, or the selection bar    [Select] [Search <page>  ⌘K]   <- row 2: this page's own controls on the left, then Select and Search
///
/// The search field has one width, height, radius and ⌘K hint everywhere and stays on the right of row 2 even when a page has
/// no filters. `onSelect` is nil when there is nothing to select (the Select button is left out; Search does not move).
struct PageHeader<Filters: View>: View {
    let title: String
    var subtitle: String?
    var plus: (() -> Void)?
    /// What VoiceOver calls the round plus button.
    var plusLabel = "Add"
    var onSelect: (() -> Void)?
    @ViewBuilder var filters: () -> Filters

    var body: some View {
        VStack(alignment: .leading, spacing: Look.toolbarGap) {
            HStack(spacing: 14) {
                if let plus {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Look.card, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                        .contentShape(Circle())
                        .accessibleTap(plusLabel, combine: false, plus)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Look.pageTitle)
                    if let subtitle { Text(subtitle).font(Look.body).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 40)
            HStack(spacing: 10) {
                filters()
                Spacer(minLength: 12)
                if let onSelect {
                    Button(action: onSelect) { HeaderButtonLabel(title: "Select", symbol: "checkmark.circle") }.buttonStyle(.plain)
                }
                SearchBarButton()
            }
            .frame(minHeight: Look.controlHeight)
        }
        .zIndex(10)
    }
}

/// What a page shows when it has nothing to list: an icon tile, a title, one or two lines about what belongs here, and the one
/// action that fills it. Centred in the space under the header, a little above the middle.
struct EmptyState: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    let message: String
    var actionTitle: String?
    var actionSymbol: String?
    var action: (() -> Void)?
    /// A quiet line under the button, for the other way in ("or drag files here").
    var hint: String?
    @StateObject private var hovering = Box(false)

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true)
                .frame(width: 64, height: 64)
                .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            Text(title).font(Look.sectionTitle).padding(.top, 18)
            Text(message).font(Look.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380).padding(.top, 6)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 7) {
                        if let actionSymbol { Image(systemName: actionSymbol).font(.system(size: 12.5, weight: .semibold)) }
                        Text(actionTitle).font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: Look.controlHeight)
                    .background(Color.accentColor.opacity(hovering.value ? 0.92 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).onHover { hovering.value = $0 }.padding(.top, 20)
            }
            if let hint { Text(hint).font(Look.meta).foregroundStyle(.tertiary).padding(.top, 12) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 70).padding(.horizontal, 32)
    }
}

/// "49–96 of 213" with Previous and Next, under a long list.
struct PaginationBar: View {
    @Binding var page: Int
    let pageCount: Int
    let total: Int

    var body: some View {
        let first = page * Look.pageSize + 1
        let last = min(total, (page + 1) * Look.pageSize)
        HStack(spacing: 10) {
            Text("\(first)–\(last) of \(total)").font(Look.meta).foregroundStyle(.secondary)
            Spacer()
            step("chevron.left", enabled: page > 0, help: "Previous page") { page -= 1 }
            Text("Page \(page + 1) of \(pageCount)").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(minWidth: 86)
            step("chevron.right", enabled: page < pageCount - 1, help: "Next page") { page += 1 }
        }
        .padding(.top, 8)
    }

    private func step(_ symbol: String, enabled: Bool, help: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 28).background(Color.primary.opacity(0.07), in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).help(help).accessibilityLabel(help)
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

// MARK: - Accessibility

extension View {
    /// A click target that VoiceOver can find and press. `onTapGesture` alone is invisible to it, so this adds the button trait,
    /// an optional label and hint, the selected state, and the same action as a VoiceOver activation.
    /// `combine: true` reads the text inside the view; `false` reads only `label` (for icon-only controls).
    func accessibleTap(_ label: String? = nil, hint: String? = nil, selected: Bool = false, combine: Bool = true,
                       _ action: @escaping () -> Void) -> some View {
        self.onTapGesture(perform: action)
            .accessibilityElement(children: combine ? .combine : .ignore)
            .modifier(A11yText(label: label, hint: hint))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}

/// Sets a label and hint only when given, so a view that combines its children keeps reading their text.
private struct A11yText: ViewModifier {
    let label: String?
    let hint: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let label, let hint { content.accessibilityLabel(label).accessibilityHint(hint) }
        else if let label { content.accessibilityLabel(label) }
        else if let hint { content.accessibilityHint(hint) }
        else { content }
    }
}

/// What VoiceOver should call an icon-only control, from its SF Symbol.
func symbolLabel(_ symbol: String) -> String {
    switch symbol {
    case "magnifyingglass": "Search"
    case "star", "star.fill": "Pinned only"
    case "pause.circle.fill": "Resume recording"
    case "record.circle": "Pause recording"
    case "gearshape": "Settings"
    case "plus": "Add"
    case "ellipsis": "More options"
    case "list.bullet": "All notes"
    case "pin": "Pin"
    case "pin.fill": "Unpin"
    case "trash": "Delete"
    default: symbol
    }
}
