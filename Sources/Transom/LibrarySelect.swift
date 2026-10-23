import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The page header's buttons and the look of Select mode in the Library.

/// A button in a page header, the same height and outline as the search field beside it.
struct HeaderButtonLabel: View {
    let title: String
    let symbol: String
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: Look.controlHeight)
        .background(Look.card.opacity(hovering.value ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
    }
}

/// The same pill for every action in the selection bar: 30 pt tall, 13 pt medium, icon and text 6 pt apart.
struct SelectBarLabel: View {
    let title: String
    var symbol: String?
    var tint: Color?
    var chevron = false
    var filled = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
            Text(title).font(.system(size: 13, weight: .medium))
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.7) }
        }
        .foregroundStyle(filled ? Look.card : (tint ?? Color.primary))
        .padding(.horizontal, 12).frame(height: 30)
        .background(filled ? Color.primary : Color.primary.opacity(0.07), in: Capsule())
        .contentShape(Capsule())
    }
}

/// Selection chrome on a card or row: flat until the pointer is over it, then a soft ring and an empty circle inside
/// the card's lower left; picked items keep the full ring and a filled check.
struct SelectChrome: View {
    let on: Bool
    let radius: CGFloat
    let toggle: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        let show = on || hovering.value
        // Cards: lower left, inside. Rows are short, so there it sits at the leading edge, centred.
        let compact = radius <= 10
        ZStack(alignment: compact ? .leading : .bottomLeading) {
            Color.clear.contentShape(Rectangle())
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(on ? 1 : (hovering.value ? 0.5 : 0)), lineWidth: 2.5)
                .shadow(color: Color.accentColor.opacity(on ? 0.45 : (hovering.value ? 0.25 : 0)), radius: 8)
                .allowsHitTesting(false)
            ZStack {
                Circle().fill(on ? Color.accentColor : Color.black.opacity(0.35))
                Circle().strokeBorder(.white.opacity(on ? 0 : 0.9), lineWidth: 1.5)
                if on { Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 22, height: 22)
            .padding(compact ? 6 : 12)
            .opacity(show ? 1 : 0)
            .scaleEffect(show ? 1 : 0.85)
            .allowsHitTesting(false)
        }
        .onHover { hovering.value = $0 }
        .accessibleTap("Select item", selected: on, combine: false, toggle)
        .animation(.easeOut(duration: 0.14), value: show)
        .animation(.easeOut(duration: 0.14), value: on)
    }
}
