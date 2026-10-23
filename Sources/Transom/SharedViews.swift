import SwiftUI
import AppKit
// Small pieces the three columns share: header icons, the panel menu, the type pill, cover thumbnails and haptics.

struct HeaderIcon: View {
    let symbol: String
    var active = false
    /// Sits on a soft background even at rest, so the main action stands out from its neighbours.
    var filled = false
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: fs(12), weight: .medium))
            .foregroundStyle(active ? Color.accentColor : (hovering.value ? Color.primary : Color.secondary))
            .frame(width: 26, height: 26)
            .background(hovering.value ? Color.primary.opacity(0.14) : (filled || active ? Color.primary.opacity(0.08) : .clear),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering.value = $0 }
            .accessibleTap(symbolLabel(symbol), selected: active, combine: false, action)
    }
}

/// The "⋯" button each panel has for its own options.
struct PanelMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Menu { content() } label: {
            Image(systemName: "ellipsis").font(.system(size: fs(12), weight: .medium)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26, height: 26)
        .help("Panel options")
    }
}

struct ColumnHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 2) {
            Text(title).font(.system(size: fs(13), weight: .semibold)).foregroundStyle(.primary.opacity(0.7))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}

struct Pill: View {
    let category: Category
    var sensitive = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sensitive ? "lock.fill" : category.symbol).font(.system(size: fs(9), weight: .semibold))
            Text(sensitive ? "Sensitive" : category.label).font(.system(size: fs(10), weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(Contrast.solidChips ? Color.white : category.tint)
        .background(Contrast.solidChips ? category.tint : category.tint.opacity(0.16), in: Capsule())
    }
}

/// Cover art loaded from QuickLook.
struct Thumb: View {
    let url: URL
    let size: CGSize
    var fill = true
    @StateObject private var img = Box<NSImage?>(nil)

    var body: some View {
        Group {
            if let i = img.value {
                if fill { Image(nsImage: i).resizable().scaledToFill() } else { Image(nsImage: i).resizable().scaledToFit() }
            } else {
                Color.primary.opacity(fill ? 0.05 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: url) { img.value = await Thumbs.image(for: url, size: size) ?? NSWorkspace.shared.icon(forFile: url.path) }
    }
}

/// Quiet heading that groups clipboard rows by how recently they were copied.
struct GroupHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: fs(11.5), weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
    }
}

enum Haptics {
    private static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
    /// The click you feel on a Force Touch trackpad when something lines up. Does nothing on a mouse.
    static func detent() { play(.alignment) }
    /// Picking something up, moving it over a new slot, and putting it down.
    static func pickup() { play(.generic) }
    static func tick() { play(.alignment) }
    static func drop() { play(.levelChange) }
}
