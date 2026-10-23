import SwiftUI
import AppKit

/// Stand-in for @State: the Command Line Tools SDK lacks the SwiftUI macro plugin that @State needs.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Transom

struct TransomView: View {
    @ObservedObject var layout = AppModel.shared.layout
    @ObservedObject var settings = Settings.shared
    private let handleWidth: CGFloat = 12
    private let minPanelWidth: CGFloat = 180
    @StateObject private var snapped = Box(false)

    var body: some View {
        let v = settings.v
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
        let tint = Color(nsColor: .windowBackgroundColor).opacity(v.translucency)
        let shown = v.orderedPanels.filter { v.isShown($0) }
        ZStack(alignment: .bottom) {
            GeometryReader { geo in panelRow(shown, width: geo.size.width, gearOn: shown.last) }
            .padding(.top, layout.topInset)
            HeightHandle()
        }
        .contentShape(Rectangle())
        .contextMenu { AppMenuItems() }
        .glassSurface(shape, tint: tint, enabled: v.liquidGlass)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    /// Panels side by side with draggable dividers.
    @ViewBuilder private func panelRow(_ shown: [Panel], width: CGFloat, gearOn: Panel?) -> some View {
        let v = settings.v
        let avail = max(1, width - handleWidth * CGFloat(max(0, shown.count - 1)))
        let total = shown.reduce(0) { $0 + v.weight($1) }
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, p in
                column(p, gear: p == gearOn)
                    .frame(width: avail * v.weight(p) / total)
                if i < shown.count - 1 {
                    PanelDivider(width: handleWidth) { start, dx in
                        resize(left: p, right: shown[i + 1], start: start, dx: dx, avail: avail, total: total, count: shown.count)
                    } begin: { (v.weight(p), v.weight(shown[i + 1])) }
                }
            }
            if shown.isEmpty {
                Text("All panels are hidden. Right-click here to bring some back.")
                    .font(.system(size: fs(13))).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func column(_ p: Panel, gear: Bool) -> some View {
        switch p {
        case .clipboard: ClipboardColumn(store: AppModel.shared.clipboard, showsGear: gear, cards: settings.v.clipboardCards)
            .overlay(alignment: .bottom) { ClearConfirmBar(store: AppModel.shared.clipboard) }
        case .files: FilesColumn(store: AppModel.shared.files, showsGear: gear)
        case .notes: NotesColumn(store: AppModel.shared.notes, showsGear: gear)
        }
    }

    /// Move the divider between two neighbours; the pair keeps its combined share of the width.
    private func resize(left: Panel, right: Panel, start: (Double, Double), dx: CGFloat, avail: CGFloat, total: Double, count: Int) {
        let perPoint = total / Double(avail)
        let pair = start.0 + start.1
        let minW = Double(minPanelWidth) * perPoint
        guard pair > minW * 2 else { return }
        var l = min(max(start.0 + Double(dx) * perPoint, minW), pair - minW)
        // The default split is a detent: pull towards it and give a tap of haptic feedback on arrival.
        var d = SettingsValues()
        d.clipboardCards = settings.v.clipboardCards
        let equal = min(max(pair * d.weight(left) / (d.weight(left) + d.weight(right)), minW), pair - minW)
        let near = abs(l - equal) < 8 * perPoint
        if near {
            l = equal
            if !snapped.value { Haptics.detent() }
        }
        snapped.value = near
        settings.v.setWeight(left, l)
        settings.v.setWeight(right, pair - l)
    }
}

enum Panel: String, Codable, CaseIterable {
    case clipboard, files, notes
    var title: String {
        switch self { case .clipboard: "Clipboard"; case .files: "Quick Access"; case .notes: "Notes" }
    }
    var symbol: String {
        switch self { case .clipboard: "doc.on.clipboard"; case .files: "folder"; case .notes: "note.text" }
    }
}

/// The line between two panels. Hovering shows a grab handle; dragging resizes the panels either side.
struct PanelDivider: View {
    let width: CGFloat
    let change: ((Double, Double), CGFloat) -> Void
    let begin: () -> (Double, Double)
    @StateObject private var hovering = Box(false)
    @StateObject private var start = Box<(Double, Double)?>(nil)

    var body: some View {
        let active = hovering.value || start.value != nil
        ZStack {
            Rectangle().fill(active ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 14)
            Capsule().fill(Color.primary.opacity(0.45)).frame(width: 4, height: 38).opacity(active ? 1 : 0)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside != hovering.value else { return }
            hovering.value = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if start.value == nil { start.value = begin() }
                    if let s = start.value { change(s, g.translation.width) }
                }
                .onEnded { _ in start.value = nil }
        )
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Grab strip on the drawer's bottom edge: drag to change the drawer height.
struct HeightHandle: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var hovering = Box(false)
    @StateObject private var startHeight = Box<Double?>(nil)
    @StateObject private var snapped = Box(false)

    var body: some View {
        let active = hovering.value || startHeight.value != nil
        ZStack {
            Capsule().fill(Color.primary.opacity(0.45)).frame(width: 46, height: 4).opacity(active ? 1 : 0)
        }
        .frame(maxWidth: .infinity).frame(height: 14)
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside != hovering.value else { return }
            hovering.value = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if startHeight.value == nil { startHeight.value = settings.v.activeHeight }
                    let limit = Double((NSScreen.main?.frame.height ?? 900) - 120)
                    var h = min(max((startHeight.value ?? 300) + Double(g.translation.height), 200), limit)
                    // The default height is a detent: it snaps there with a tap of haptic feedback.
                    let near = abs(h - settings.v.defaultActiveHeight) < 8
                    if near {
                        h = settings.v.defaultActiveHeight
                        if !snapped.value { Haptics.detent() }
                    }
                    snapped.value = near
                    settings.v.activeHeight = h
                }
                .onEnded { _ in startHeight.value = nil }
        )
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Menu for right-clicking anywhere on the drawer that is not a row of its own.
struct AppMenuItems: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Button(settings.v.paused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") { settings.v.paused.toggle() }
        Divider()
        Menu("Panels") {
            CheckButton("Clipboard", settings.v.showClipboard) { settings.v.showClipboard.toggle() }
            CheckButton("Quick Access", settings.v.showFiles) { settings.v.showFiles.toggle() }
            CheckButton("Notes", settings.v.showNotes) { settings.v.showNotes.toggle() }
        }
        Divider()
        Button("Settings…") { AppModel.shared.openSettings(nil) }
        Button("Clipboard Settings…") { AppModel.shared.openSettings(.clipboard) }
        Button("Quick Access Settings…") { AppModel.shared.openSettings(.files) }
        Button("Notes Settings…") { AppModel.shared.openSettings(.notes) }
        Divider()
        Button("Close Transom") { AppModel.shared.hideDrawer() }
    }
}

/// A menu item with a checkmark when selected.
struct CheckButton: View {
    let title: String
    let checked: Bool
    let action: () -> Void
    init(_ title: String, _ checked: Bool, action: @escaping () -> Void) { self.title = title; self.checked = checked; self.action = action }
    var body: some View {
        Button(action: action) {
            if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

// MARK: - Shared pieces

// MARK: - Clipboard

// MARK: - Files

// MARK: - Notes

// MARK: - Expanded clip

// MARK: - Files options

// MARK: - Cards

