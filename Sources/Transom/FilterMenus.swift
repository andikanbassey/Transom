import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The Time, Type and App filter menus used in the drawer and the Library.

/// A dropdown in the filter row: an icon, the value it is set to now, and a chevron. Grey while it is on its default,
/// accent-coloured once it filters something.
struct FilterMenuLabel: View {
    let symbol: String
    var image: NSImage?
    let value: String
    let active: Bool
    /// The drawer's size and spacing; the Library's is larger.
    var compact = false
    /// In a narrow drawer column the text is left off until the filter is on.
    var showsText = true

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            if let image { Image(nsImage: image).resizable().frame(width: compact ? 14 : 16, height: compact ? 14 : 16) }
            else { Image(systemName: symbol).font(.system(size: compact ? fs(10.5) : 12, weight: .medium)) }
            if showsText || active || !compact { Text(value).font(.system(size: compact ? fs(11) : 13, weight: .medium)).lineLimit(1) }
            Image(systemName: "chevron.down").font(.system(size: compact ? 7 : 9, weight: .semibold))
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .padding(.horizontal, compact ? 9 : 14).frame(height: compact ? 26 : Look.controlHeight)
        .background(active ? Color.accentColor.opacity(0.14) : Color.primary.opacity(compact ? 0.07 : 0.055),
                    in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }
}

/// When it was copied: Any time, Last hour, Today…
struct TimeMenu: View {
    @ObservedObject var store: ClipboardStore
    var compact = false
    var showsText = true
    var body: some View {
        Menu {
            // A Toggle per choice is how a menu gets its tick; a Picker here left an empty row above the first item.
            ForEach(TimeFilter.allCases, id: \.self) { t in
                Toggle(isOn: Binding(get: { store.time == t }, set: { if $0 { store.time = t } })) { Text(t.rawValue) }
            }
        } label: { FilterMenuLabel(symbol: "clock", value: store.time.rawValue, active: store.time != .any, compact: compact, showsText: showsText) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
            .contextMenu { ClearUnpinnedButton(store: store) }
    }
}

/// What kind of item: All types, Text, Links, Images…
struct TypeMenu: View {
    @ObservedObject var store: ClipboardStore
    var compact = false
    var showsText = true
    var body: some View {
        let current = store.filter
        Menu {
            ForEach(Category.Filter.allCases, id: \.self) { f in
                Toggle(isOn: Binding(get: { store.filter == f }, set: { if $0 { store.filter = f } })) {
                    Label(f == .all ? "All types" : f.rawValue, systemImage: FilterIcon.symbol(f))
                }
            }
        } label: {
            FilterMenuLabel(symbol: FilterIcon.symbol(current), value: current == .all ? "All types" : current.rawValue, active: current != .all, compact: compact, showsText: showsText)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
        .contextMenu { ClearUnpinnedButton(store: store) }
    }
}

/// Which app it was copied from: All apps, or one of the apps in the history.
struct AppMenu: View {
    @ObservedObject var store: ClipboardStore
    var compact = false
    var showsText = true

    private func small(_ bundle: String?) -> NSImage? {
        guard let icon = AppIcons.icon(bundle) else { return nil }
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in icon.draw(in: r); return true }
        return img
    }

    var body: some View {
        let apps = store.appsInHistory
        let current = apps.first { $0.key == store.appFilter }
        Menu {
            Toggle(isOn: Binding(get: { store.appFilter == nil }, set: { if $0 { store.appFilter = nil } })) {
                Label("All apps", systemImage: "square.grid.2x2")
            }
            if !apps.isEmpty { Divider() }
            ForEach(apps, id: \.key) { app in
                Toggle(isOn: Binding(get: { store.appFilter == app.key }, set: { if $0 { store.appFilter = app.key } })) {
                    if let icon = small(app.bundle) {
                        Label { Text("\(app.name) (\(app.count))") } icon: { Image(nsImage: icon) }
                    } else {
                        Text("\(app.name) (\(app.count))")
                    }
                }
            }
        } label: {
            FilterMenuLabel(symbol: "app.dashed", image: small(current?.bundle), value: current?.name ?? "All apps", active: current != nil, compact: compact, showsText: showsText)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
        .contextMenu { ClearUnpinnedButton(store: store) }
    }
}
