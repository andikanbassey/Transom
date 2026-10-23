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

// MARK: - Clipboard

/// How recently an item was copied. Pinned items sit above everything else.
enum TimeGroup: CaseIterable {
    case pinned, hour, today, yesterday, week, month, older

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .hour: "Past Hour"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "This Week"
        case .month: "This Month"
        case .older: "Older"
        }
    }

    static func of(_ clip: Clip, now: Date = Date()) -> TimeGroup {
        if clip.pinned { return .pinned }
        let age = now.timeIntervalSince(clip.date)
        let cal = Calendar.current
        if age < 3600 { return .hour }
        if cal.isDateInToday(clip.date) { return .today }
        if cal.isDateInYesterday(clip.date) { return .yesterday }
        if age < 7 * 86_400 { return .week }
        if age < 30 * 86_400 { return .month }
        return .older
    }
}

struct ClipboardColumn: View {
    @ObservedObject var store: ClipboardStore
    var showsGear: Bool
    var cards = false
    @FocusState private var searchFocused: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var columnWidth = Box<CGFloat>(900)

    var body: some View {
        let visible = store.visible
        let now = Date()
        let index = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1.id, $0) })
        let groups = TimeGroup.allCases.compactMap { g -> (TimeGroup, [Clip])? in
            let items = visible.filter { TimeGroup.of($0, now: now) == g }
            return items.isEmpty ? nil : (g, items)
        }
        VStack(spacing: 0) {
            // Title on the left, the three filters in the middle, the actions on the right: search first and filled so it
            // stands out, then pinned-only, pause and the menu.
            HStack(spacing: 0) {
                Text("Clipboard History").font(.system(size: fs(13), weight: .semibold)).foregroundStyle(.primary.opacity(0.7)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    TimeMenu(store: store, compact: true, showsText: columnWidth.value > 600)
                    TypeMenu(store: store, compact: true, showsText: columnWidth.value > 600)
                    AppMenu(store: store, compact: true, showsText: columnWidth.value > 600)
                }
                .layoutPriority(1)
                HStack(spacing: 2) {
                    HeaderIcon(symbol: "magnifyingglass", active: store.searching, filled: true) {
                        store.searching.toggle()
                        if !store.searching { store.query = "" }
                    }
                    .help("Search clipboard (⌘F)")
                    HeaderIcon(symbol: store.pinnedOnly ? "star.fill" : "star", active: store.pinnedOnly) { store.pinnedOnly.toggle() }
                        .help("Pinned only")
                    HeaderIcon(symbol: settings.v.paused ? "pause.circle.fill" : "record.circle", active: settings.v.paused) {
                        settings.v.paused.toggle()
                    }
                    .help(settings.v.paused ? "Clipboard capture paused" : "Pause clipboard capture")
                    PanelMenu {
                        Button(settings.v.paused ? "Resume Capture" : "Pause Capture") { settings.v.paused.toggle() }
                        ClearUnpinnedButton(store: store)
                        Divider()
                        Button("Clipboard Settings…") { AppModel.shared.openSettings(.clipboard) }
                        Button("Hide Clipboard Panel") { settings.v.showClipboard = false }
                    }
                    if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { columnWidth.value = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in columnWidth.value = w }
            })
            if store.expanded == nil, store.searching {
                TextField("Search clipboard", text: $store.query)
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
                    .textFieldStyle(.plain).font(.system(size: fs(12)))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            if let clip = store.expanded {
                ExpandedClipView(clip: clip, store: store)
            } else if visible.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: fs(22))).foregroundStyle(.tertiary)
                    Text(store.clips.isEmpty ? "Copy something to see it here" : "No matches")
                        .font(.system(size: fs(12))).foregroundStyle(.tertiary)
                }
                Spacer()
            } else if cards {
                GeometryReader { geo in
                    // Captions and gaps by age (Pinned, Past Hour, Today, Yesterday...) as soon as there is more than one group.
                    let sections = groups.count > 1
                    let cardHeight = max(110, geo.size.height - 16 - (sections ? 22 : 0))
                    // Cards keep one shape and scale with the drawer: laid out at a base size, then scaled as a whole.
                    let scale = min(2.4, max(0.7, cardHeight / ClipCard.baseHeight))
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            if sections {
                                ForEach(Array(groups.enumerated()), id: \.element.0) { n, entry in
                                    if n > 0 {
                                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                                            .padding(.vertical, 6).padding(.horizontal, 14)
                                    }
                                    cardSection(entry.0.title, symbol: entry.0 == .pinned ? "pin.fill" : "clock",
                                                items: entry.1, index: index, scale: scale)
                                }
                            } else {
                                cardSection(nil, symbol: "", items: visible, index: index, scale: scale)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .mask(edgeFade)
                    .onChange(of: store.cursor) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(groups, id: \.0) { group, items in
                                GroupHeader(title: group.title)
                                ForEach(items) { clip in
                                    let n = index[clip.id] ?? 99
                                    ClipRow(clip: clip, store: store, quickKey: settings.v.quickPaste && n < 9 ? n + 1 : nil).id(clip.id)
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 10)
                    }
                    .onChange(of: store.cursor) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }
}

extension ClipboardColumn {
    /// A run of cards with an optional caption above it.
    fileprivate func cardSection(_ title: String?, symbol: String, items: [Clip], index: [UUID: Int], scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Label(title, systemImage: symbol)
                    .font(.system(size: fs(11.5), weight: .semibold)).foregroundStyle(.secondary).frame(height: 18)
            }
            LazyHStack(spacing: 10) {
                ForEach(items) { clip in
                    let n = index[clip.id] ?? 99
                    ClipCard(clip: clip, store: store, quickKey: settings.v.quickPaste && n < 9 ? n + 1 : nil)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: store.cursor == clip.id ? 3 : 0))
                        .id(clip.id)
                        .frame(width: ClipCard.baseWidth, height: ClipCard.baseHeight)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: ClipCard.baseWidth * scale, height: ClipCard.baseHeight * scale, alignment: .topLeading)
                }
            }
        }
    }

    /// A very soft fade at both ends hints that the strip scrolls sideways.
    fileprivate var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 22)
        }
    }
}

/// Media type selector shown in the card drawer's header.
enum FilterIcon {
    static func symbol(_ f: Category.Filter) -> String {
        switch f {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .color: "paintpalette"
        case .video: "play.rectangle"
        case .files: "doc"
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let store: ClipboardStore
    var quickKey: Int?
    /// In the Library a click copies; in the drawer it pastes into the app underneath.
    var inWindow = false
    @StateObject private var hovering = Box(false)
    private let cover: CGFloat = 54

    var body: some View {
        let cat = clip.category
        HStack(spacing: 10) {
            Image(systemName: clip.pinned ? "star.fill" : "star")
                .font(.system(size: fs(11)))
                .foregroundStyle(clip.pinned ? Color.yellow : Color.secondary.opacity(hovering.value ? 0.8 : 0))
                .frame(width: 14)
                .contentShape(Rectangle())
                .accessibleTap(clip.pinned ? "Unpin" : "Pin", combine: false) { store.togglePin(clip) }
            coverArt(cat)
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: fs(13.5), weight: .medium))
                    .lineLimit(cat == .text ? 2 : 1).truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Pill(category: cat, sensitive: clip.sensitive)
                    if let expiry = clip.sensitiveExpiry { SensitiveClock(expiry: expiry) }
                }
            }
            Spacer(minLength: 4)
            ZStack {
                if hovering.value {
                    Image(systemName: "xmark").font(.system(size: fs(10), weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .accessibleTap("Delete", combine: false) { store.delete(clip) }
                } else {
                    HStack(spacing: 6) {
                        if let icon = AppIcons.icon(clip.sourceBundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18).opacity(0.85)
                        }
                        if let n = quickKey {
                            Text("\(Settings.shared.v.quickPasteModifier.symbol)\(n)")
                                .font(.system(size: fs(10), weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(store.cursor == clip.id ? Color.accentColor.opacity(0.22) : (hovering.value ? Color.primary.opacity(0.08) : .clear),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .accessibleTap(hint: "Pastes or copies the item") {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip }
            else if inWindow { store.copy(clip); if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() } }
            else { AppModel.shared.use(clip) }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { if inWindow { LibraryClipMenu(clip: clip, store: store) } else { ClipMenu(clip: clip, store: store) } }
    }

    /// A square cover that says what the clip is: real artwork for media, a tinted symbol for the rest.
    @ViewBuilder private func coverArt(_ cat: Category) -> some View {
        let size = CGSize(width: cover, height: cover)
        if clip.sensitive {
            SensitiveCover(clip: clip, active: hovering.value)
        } else {
        switch cat {
        case .color:
            (Clip.hexColor((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .gray)
        case .image, .gif, .video:
            ZStack {
                if let url = clip.previewURL { Thumb(url: url, size: size) }
                if cat == .video {
                    Image(systemName: "play.fill").font(.system(size: fs(10))).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle())
                }
            }
        case .pdf, .folder, .file:
            ZStack {
                Color.primary.opacity(0.06)
                if let url = clip.previewURL { Thumb(url: url, size: CGSize(width: cover - 8, height: cover - 8), fill: false) }
            }
        case .link where clip.linkImageURL != nil:
            Thumb(url: clip.linkImageURL!, size: size)
        case .text, .link, .audio:
            ZStack {
                Contrast.solidChips ? cat.tint : cat.tint.opacity(0.18)
                Image(systemName: cat == .text ? "text.alignleft" : cat.symbol)
                    .font(.system(size: fs(20), weight: .medium)).foregroundStyle(Contrast.solidChips ? Color.white : cat.tint)
            }
        }
        }
    }
}

// MARK: - Files

// MARK: - Notes

// MARK: - Expanded clip

/// A single clipboard item shown in full inside the clipboard column.
struct ExpandedClipView: View {
    let clip: Clip
    let store: ClipboardStore
    var inWindow = false

    var body: some View {
        let cat = clip.category
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { store.expanded = nil } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Pill(category: cat, sensitive: clip.sensitive)
                if let expiry = clip.sensitiveExpiry { SensitiveClock(expiry: expiry) }
                Spacer()
                Button("Copy") {
                    store.copy(clip)
                    if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
                }
                if !inWindow { Button("Paste") { AppModel.shared.use(clip, paste: true) }.keyboardShortcut(.defaultAction) }
            }
            .padding(.horizontal, 14)
            content(cat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12).padding(.bottom, 14)
        }
    }

    @ViewBuilder private func content(_ cat: Category) -> some View {
        if clip.sensitive && ![.text, .link, .color].contains(cat) {
            SensitiveCover(clip: clip, active: true)
        } else {
        switch cat {
        case .text, .link, .color:
            ScrollView {
                if clip.sensitive {
                    SensitiveText(length: (clip.text ?? "").count, active: true, size: fs(13), expiry: clip.sensitiveExpiry)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } else {
                    Text(clip.text ?? clip.title)
                        .font(.system(size: fs(13))).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
            }
        case .image, .gif:
            if let url = clip.imageURL ?? clip.fileURLs.first, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().padding(8)
            } else {
                Text("Preview unavailable").foregroundStyle(.secondary)
            }
        default:
            GeometryReader { geo in
                VStack(spacing: 8) {
                    if let url = clip.previewURL {
                        Thumb(url: url, size: CGSize(width: geo.size.width - 20, height: max(40, geo.size.height - 70)), fill: false)
                    }
                    Text(clip.fileURLs.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.system(size: fs(12))).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        }
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

// MARK: - Files options

/// The preview area of a card: text excerpt, link cover, colour, picture or file thumbnail.
struct ClipPreview: View {
    let clip: Clip
    @StateObject private var hovering = Box(false)

    var body: some View { preview(clip.category).onHover { hovering.value = $0 } }

    @ViewBuilder private func preview(_ cat: Category) -> some View {
        GeometryReader { geo in
            if clip.sensitive && cat != .text {
                SensitiveCover(clip: clip, active: hovering.value)
            } else {
            switch cat {
            case .color:
                ZStack {
                    (Clip.hexColor((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .gray)
                    Text(clip.title).font(.system(size: fs(15), weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).shadow(radius: 2)
                }
            case .image, .gif, .video:
                ZStack {
                    if let url = clip.previewURL { Thumb(url: url, size: geo.size) }
                    if cat == .video {
                        Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(.black.opacity(0.55), in: Circle())
                    }
                }
            case .pdf, .folder, .file, .audio:
                ZStack {
                    Color.primary.opacity(0.04)
                    if let url = clip.previewURL {
                        Thumb(url: url, size: CGSize(width: geo.size.width - 20, height: geo.size.height - 12), fill: false)
                    }
                }
            case .link:
                VStack(alignment: .leading, spacing: 4) {
                    if let img = clip.linkImageURL {
                        Thumb(url: img, size: CGSize(width: geo.size.width, height: max(40, geo.size.height - 50)))
                    } else {
                        ZStack { cat.tint.opacity(0.15); Image(systemName: "link").font(.system(size: 24)).foregroundStyle(cat.tint) }
                            .frame(height: max(40, geo.size.height - 50))
                    }
                    Text(clip.title).font(.system(size: fs(12.5), weight: .semibold)).lineLimit(1).padding(.horizontal, 10)
                    Text(host).font(.system(size: fs(11))).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 10)
                }
            case .text:
                Group {
                    if clip.sensitive {
                        SensitiveText(length: (clip.text ?? "").count, active: hovering.value, size: fs(12.5), expiry: clip.sensitiveExpiry)
                    } else {
                        Text(clip.text ?? "").font(.system(size: fs(12.5))).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            }
            }
        }
    }

    private var host: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host?.replacingOccurrences(of: "www.", with: "") ?? t
    }

}

/// Right-click menu shared by clipboard rows and cards.
struct ClipMenu: View {
    let clip: Clip
    let store: ClipboardStore
    var body: some View {
        Button("Open in Full") { store.expanded = clip }
        Button("Paste") { AppModel.shared.use(clip, paste: true) }
        Divider()
        if !clip.sensitive { Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip) } }
        SensitiveToggleButton(clip: clip, store: store)
        if !clip.sensitive, let first = clip.fileURLs.first {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first]) }
        }
        if let id = clip.sourceBundleID, let name = clip.sourceApp {
            Button("Never Record from \(name)") {
                Settings.shared.block(AppRef(bundleID: id, name: name))
                Settings.shared.v.captureMode = .blockList
            }
        }
        Button("Delete") { store.delete(clip) }
        Divider()
        AppMenuItems()
    }
}

// MARK: - Cards

/// A clipboard item as a card: coloured header with type and age, a preview, and a footer with the details.
struct ClipCard: View {
    static let baseWidth: CGFloat = 196
    static let baseHeight: CGFloat = 230
    let clip: Clip
    let store: ClipboardStore
    var quickKey: Int?
    /// In the Library window there is no app to paste into, so a click copies and says so.
    var inWindow = false
    @StateObject private var hovering = Box(false)
    @StateObject private var copied = Box(false)

    var body: some View {
        let cat = clip.category
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: clip.kindSymbol).font(.system(size: fs(11), weight: .semibold))
                        Text(clip.kindLabel).font(.system(size: fs(13), weight: .semibold))
                    }
                    Text(clip.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: fs(10.5))).opacity(0.85)
                }
                .frame(height: fs(38))
                Spacer(minLength: 4)
                // Same height as the title block, so where an item came from reads at a glance.
                if let icon = AppIcons.icon(clip.sourceBundleID) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: fs(38), height: fs(38))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(cat.tint)

            ClipPreview(clip: clip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            HStack {
                if let expiry = clip.sensitiveExpiry {
                    SensitiveClock(expiry: expiry)
                } else {
                    Text(footer(cat)).font(.system(size: fs(10.5))).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let n = quickKey {
                    Text("\(Settings.shared.v.quickPasteModifier.symbol)\(n)")
                        .font(.system(size: fs(10), weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(hovering.value ? cat.tint : Color.primary.opacity(0.1), lineWidth: hovering.value ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if hovering.value {
                HStack(spacing: 6) {
                    cardButton(clip.pinned ? "pin.fill" : "pin") { store.togglePin(clip) }
                    cardButton("trash") { store.delete(clip) }
                }
                .padding(.top, 8).padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .overlay {
            if copied.value {
                Text("Copied").font(.system(size: fs(13), weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(.black.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .accessibleTap(hint: "Copies the item") {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip; return }
            if inWindow {
                store.copy(clip)
                if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
                withAnimation(.easeOut(duration: 0.15)) { copied.value = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { copied.value = false } }
            } else {
                AppModel.shared.use(clip)
            }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { ClipMenu(clip: clip, store: store) }
    }

    private func cardButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(.black.opacity(0.55), in: Circle())
            .contentShape(Circle()).accessibleTap(symbolLabel(symbol), combine: false, action)
    }

    private var host: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host?.replacingOccurrences(of: "www.", with: "") ?? t
    }

    private func footer(_ cat: Category) -> String {
        switch cat {
        case .text: return clip.sensitive ? "Hidden" : "\((clip.text ?? "").count) characters"
        case .link: return host
        case .color: return "Color"
        case .image where clip.imageURL != nil: return clip.imageURL.flatMap(Thumbs.dimensions) ?? "Image"
        default:
            guard let url = clip.fileURLs.first else { return cat.label }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            let name = clip.fileURLs.count > 1 ? "\(url.lastPathComponent) + \(clip.fileURLs.count - 1)" : url.lastPathComponent
            return [name, size].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// What gets dragged out of a card or row into another app: the text, the image, or the file itself.
extension View {
    /// Takes in a clipboard item dragged from Transom's own cards or rows; anything else is ignored.
    func clipDrop(targeted: Binding<Bool>, perform: @escaping (Clip) -> Void) -> some View {
        onDrop(of: [.item], isTargeted: targeted) { _ in
            guard let clip = AppModel.shared.takeDragged() else { return false }
            perform(clip)
            Haptics.drop()
            return true
        }
    }
}

func dragProvider(_ clip: Clip) -> NSItemProvider {
    AppModel.shared.beginDrag(clip)
    switch clip.kind {
    case .text:
        return NSItemProvider(object: (clip.text ?? "") as NSString)
    case .image:
        if let url = clip.imageURL, let p = NSItemProvider(contentsOf: url) { return p }
    case .file:
        if let url = clip.fileURLs.first, let p = NSItemProvider(contentsOf: url) { return p }
    }
    return NSItemProvider(object: clip.title as NSString)
}

/// Right-click item that marks a clipboard item sensitive (masked, memory only, removed after a countdown) or undoes it.
struct SensitiveToggleButton: View {
    let clip: Clip
    let store: ClipboardStore
    var library = false
    var body: some View {
        if clip.sensitive {
            if library {
                Button { store.unmarkSensitive(clip) } label: { Label("Not Sensitive", systemImage: "lock.open") }
            } else {
                Button("Not Sensitive") { store.unmarkSensitive(clip) }
            }
        } else if library {
            Button { store.markSensitive(clip) } label: { Label("Mark as Sensitive", systemImage: "lock") }
        } else {
            Button("Mark as Sensitive") { store.markSensitive(clip) }
        }
    }
}

/// "Clear Unpinned" that follows the filters: with Claude chosen in the app filter it clears only Claude's unpinned items.
struct ClearUnpinnedButton: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        let n = store.unpinnedShown.count
        if let scope = store.clearScopeName {
            // Asked inside the window: a system alert takes focus away and the drawer closes on that.
            Button(scope == "this selection" ? "Clear Unpinned Items Shown (\(n))…" : "Clear Unpinned from \(scope) (\(n))…") {
                store.pendingClear = .init(scope: scope, count: n)
            }
            .disabled(n == 0)
        } else {
            Button("Clear All Unpinned Items") { store.clearUnpinned() }
        }
    }
}

/// The yes/no for a filtered "Clear Unpinned", shown at the bottom of the clipboard panel so the drawer stays open.
struct ClearConfirmBar: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        if let pending = store.pendingClear {
            let what = pending.scope == "this selection" ? "the unpinned items shown" : "unpinned items from \(pending.scope)"
            HStack(spacing: 10) {
                Text("Clear \(pending.count) \(pending.count == 1 ? "item" : "items") (\(what))?")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Button("Cancel") { withAnimation { store.pendingClear = nil } }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12, weight: .medium))
                Button("Clear") {
                    store.clearUnpinnedShown()
                    withAnimation { store.pendingClear = nil }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 4).background(Color.red, in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .padding(.horizontal, 14).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: store.appFilter) { _, _ in store.pendingClear = nil }
            .onChange(of: store.filter) { _, _ in store.pendingClear = nil }
            .onChange(of: store.time) { _, _ in store.pendingClear = nil }
        }
    }
}
