import SwiftUI
import AppKit

/// Stand-in for @State: the Command Line Tools SDK lacks the SwiftUI macro plugin that @State needs.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Drawer

struct DrawerView: View {
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
        Button("Close Drawer") { AppModel.shared.hideDrawer() }
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
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: fs(12), weight: .medium))
            .foregroundStyle(active ? Color.accentColor : (hovering.value ? Color.primary : Color.secondary))
            .frame(width: 26, height: 26)
            .background(hovering.value ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering.value = $0 }
            .onTapGesture(perform: action)
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
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.system(size: fs(9), weight: .semibold))
            Text(category.label).font(.system(size: fs(10), weight: .semibold))
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

    var body: some View {
        let visible = store.visible
        let now = Date()
        let index = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1.id, $0) })
        let groups = TimeGroup.allCases.compactMap { g -> (TimeGroup, [Clip])? in
            let items = visible.filter { TimeGroup.of($0, now: now) == g }
            return items.isEmpty ? nil : (g, items)
        }
        VStack(spacing: 0) {
            ColumnHeader(title: "Clipboard History") {
                HeaderIcon(symbol: settings.v.paused ? "pause.circle.fill" : "record.circle", active: settings.v.paused) {
                    settings.v.paused.toggle()
                }
                .help(settings.v.paused ? "Clipboard capture paused" : "Pause clipboard capture")
                // Time, type and app: three small dropdowns that show their setting only once they filter.
                TimeMenu(store: store, compact: true)
                TypeMenu(store: store, compact: true)
                AppMenu(store: store, compact: true)
                HeaderIcon(symbol: store.pinnedOnly ? "star.fill" : "star", active: store.pinnedOnly) { store.pinnedOnly.toggle() }
                HeaderIcon(symbol: "magnifyingglass", active: store.searching) {
                    store.searching.toggle()
                    if !store.searching { store.query = "" }
                }
                PanelMenu {
                    Button(settings.v.paused ? "Resume Capture" : "Pause Capture") { settings.v.paused.toggle() }
                    Button("Clear Unpinned Items") { store.clearUnpinned() }
                    Divider()
                    Button("Clipboard Settings…") { AppModel.shared.openSettings(.clipboard) }
                    Button("Hide Clipboard Panel") { settings.v.showClipboard = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
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
                    let pinned = visible.filter(\.pinned)
                    let recent = visible.filter { !$0.pinned }
                    let sections = !pinned.isEmpty
                    let cardHeight = max(110, geo.size.height - 16 - (sections ? 22 : 0))
                    // Cards keep one shape and scale with the drawer: laid out at a base size, then scaled as a whole.
                    let scale = min(2.4, max(0.7, cardHeight / ClipCard.baseHeight))
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            if sections {
                                cardSection("Pinned", symbol: "pin.fill", items: pinned, index: index, scale: scale)
                                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                                    .padding(.vertical, 6).padding(.horizontal, 14)
                                if !recent.isEmpty { cardSection("Recent", symbol: "clock", items: recent, index: index, scale: scale) }
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
                .onTapGesture { store.togglePin(clip) }
            coverArt(cat)
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: fs(13.5), weight: .medium))
                    .lineLimit(cat == .text ? 2 : 1).truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                Pill(category: cat)
            }
            Spacer(minLength: 4)
            ZStack {
                if hovering.value {
                    Image(systemName: "xmark").font(.system(size: fs(10), weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .onTapGesture { store.delete(clip) }
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
        .onTapGesture {
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

// MARK: - Files

struct FilesColumn: View {
    @ObservedObject var store: FilesStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var targeted = Box(false)
    @StateObject private var optionsOpen = Box(false)

    private var gridMin: CGFloat {
        switch settings.v.filesIconSize { case .small: 64; case .medium: 84; case .large: 112 }
    }
    private var iconSize: CGFloat {
        switch settings.v.filesIconSize { case .small: 34; case .medium: 44; case .large: 62 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Quick Access") {
                HeaderIcon(symbol: "plus", action: addFiles).help(store.mode == .reference ? "Pin files or folders" : "Add files to the folder")
                HeaderIcon(symbol: "ellipsis", active: optionsOpen.value) { optionsOpen.value.toggle() }
                    .help("Quick Access options")
                    .popover(isPresented: Binding(get: { optionsOpen.value }, set: {
                        optionsOpen.value = $0
                        AppModel.shared.popoverOpen = $0
                    }), arrowEdge: .bottom) {
                        FilesOptionsPopover(store: store) { optionsOpen.value = false; AppModel.shared.popoverOpen = false }
                    }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.paths.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "pin").font(.system(size: fs(20))).foregroundStyle(.tertiary)
                    Text(store.mode == .reference ? "Drop files here or press + to pin them" : "Drop files here to keep a copy")
                        .font(.system(size: fs(12))).foregroundStyle(.tertiary)
                }
                Spacer()
            } else if settings.v.filesView == .list {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.paths, id: \.self) { path in FileListRow(path: path, store: store) }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: gridMin), spacing: 6)], spacing: 8) {
                        ForEach(store.paths, id: \.self) { path in FileTile(path: path, store: store, iconSize: iconSize) }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(targeted.value ? 0.8 : 0), lineWidth: 2).padding(6))
        .onDrop(of: [.item], isTargeted: $targeted.value) { providers in
            if let clip = AppModel.shared.takeDragged() { store.addClip(clip); Haptics.drop(); return true }
            for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
                p.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { store.add(url) }
                }
            }
            return true
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = store.mode == .reference ? "Pin" : "Add"
        // The drawer is a floating panel: lift the dialog above it.
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach(store.add) }
    }
}

func fileMenu(path: String, store: FilesStore) -> some View {
    let url = URL(fileURLWithPath: path)
    return Group {
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button(store.mode == .reference ? "Unpin" : "Move to Trash") { store.remove(path) }
        Divider()
        AppMenuItems()
    }
}

struct FileTile: View {
    let path: String
    let store: FilesStore
    let iconSize: CGFloat
    @StateObject private var hovering = Box(false)

    var body: some View {
        let url = URL(fileURLWithPath: path)
        VStack(spacing: 4) {
            Thumb(url: url, size: CGSize(width: iconSize, height: iconSize), fill: false)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(url.lastPathComponent).font(.system(size: fs(11))).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(hovering.value ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.4)
        .onHover { hovering.value = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { fileMenu(path: path, store: store) }
    }
}

struct FileListRow: View {
    let path: String
    let store: FilesStore
    @StateObject private var hovering = Box(false)

    var body: some View {
        let url = URL(fileURLWithPath: path)
        HStack(spacing: 10) {
            Thumb(url: url, size: CGSize(width: 28, height: 28), fill: false)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(url.lastPathComponent).font(.system(size: fs(13))).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering.value ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.4)
        .onHover { hovering.value = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { fileMenu(path: path, store: store) }
    }
}

// MARK: - Notes

struct NotesColumn: View {
    @ObservedObject var store: NotesStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var query = Box("")
    @StateObject private var searching = Box(false)
    @StateObject private var targeted = Box(false)
    @StateObject private var noteController = NoteEditorController()

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Notes") {
                HeaderIcon(symbol: "plus") { store.add() }.help("New note")
                HeaderIcon(symbol: "magnifyingglass", active: searching.value) {
                    searching.value.toggle()
                    if searching.value { store.showingList = true } else { query.value = "" }
                }.help("Search notes")
                HeaderIcon(symbol: "list.bullet", active: store.showingList) { store.showingList.toggle() }.help("All notes")
                PanelMenu {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.folder) }
                    Divider()
                    Button("Notes Settings…") { AppModel.shared.openSettings(.notes) }
                    Button("Hide Notes Panel") { settings.v.showNotes = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.showingList { list } else { editor }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(targeted.value ? 0.8 : 0), lineWidth: 2).padding(6))
        .clipDrop(targeted: $targeted.value) { clip in store.addClip(clip); store.showingList = true }
    }

    @ViewBuilder private var editor: some View {
        if let id = store.selectedID {
            ZStack(alignment: .topLeading) {
                if store.notes.first(where: { $0.id == id })?.text.isEmpty ?? true {
                    Text("Quick notes, phone numbers, tasks…")
                        .font(.system(size: settings.v.notesFontSize)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 19).padding(.top, 8)
                }
                // The same editor as the Library's, so a note with a picture shows the picture here as well.
                MarkdownEditor(text: store.binding(for: id), fontSize: settings.v.notesFontSize, controller: noteController)
                    .padding(.horizontal, 19).padding(.top, 4).padding(.bottom, 10)
                    .id(id)
            }
        }
    }

    private var list: some View {
        let q = query.value.trimmingCharacters(in: .whitespaces)
        let shown = store.notes.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) }
        return VStack(spacing: 6) {
            if searching.value {
                TextField("Search notes", text: $query.value)
                    .textFieldStyle(.plain).font(.system(size: fs(12)))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown) { note in NoteRow(note: note, store: store) }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let store: NotesStore
    var inWindow = false
    @StateObject private var hovering = Box(false)
    @StateObject private var confirming = Box(false)

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: fs(13.5), weight: .medium)).lineLimit(1)
                Text(note.preview.isEmpty ? note.date.formatted(date: .abbreviated, time: .omitted) : note.preview)
                    .font(.system(size: fs(12))).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if confirming.value {
                // The first click on the x only asks; this red button is the one that deletes.
                Text("Delete").font(.system(size: fs(11), weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Color.red, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { store.delete(note) }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if hovering.value {
                Image(systemName: "xmark").font(.system(size: fs(10), weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .onTapGesture {
                        confirming.value = true
                        // Not confirmed in a few seconds: back to the x.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirming.value = false }
                    }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hovering.value || note.id == store.selectedID ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: confirming.value)
        .onHover { hovering.value = $0 }
        .onTapGesture { store.select(note) }
        .contextMenu {
            NoteMenu(note: note, store: store)
            if !inWindow { Divider(); AppMenuItems() }
        }
    }
}

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
                Pill(category: cat)
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
        switch cat {
        case .text, .link, .color:
            ScrollView {
                Text(clip.text ?? clip.title)
                    .font(.system(size: fs(13))).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
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

/// The Files options as a detailed, macOS-style menu: sections, checkmarks, shortcuts and an item size slider.
struct FilesOptionsPopover: View {
    let store: FilesStore
    let close: () -> Void
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let v = settings.v
        VStack(alignment: .leading, spacing: 0) {
            if store.mode == .folder {
                OptionRow("New Folder") { store.newFolder(); close() }
                OptionRow("Show in Finder") { NSWorkspace.shared.open(FilesStore.folder); close() }
                OptionDivider()
            }
            OptionRow("Paste") { store.pasteFromClipboard(); close() }
            OptionDivider()
            OptionLabel("Arrange By")
            ForEach(FileSort.allCases, id: \.self) { s in
                OptionRow(s.label, checked: v.filesSort == s) { settings.v.filesSort = s }
            }
            OptionDivider()
            OptionRow("Keep Folders on Top", checked: v.filesFoldersOnTop) { settings.v.filesFoldersOnTop.toggle() }
            OptionDivider()
            OptionLabel("View As")
            ForEach(Array(FilesView.allCases.enumerated()), id: \.element) { i, f in
                OptionRow(f.label, checked: v.filesView == f, shortcut: "⌘\(i + 1)") { settings.v.filesView = f }
            }
            OptionDivider()
            OptionLabel("Item Size")
            HStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(FileIconSize.allCases.firstIndex(of: v.filesIconSize) ?? 1) },
                    set: { settings.v.filesIconSize = FileIconSize.allCases[min(2, max(0, Int($0.rounded())))] }
                ), in: 0...2, step: 1)
                Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            OptionDivider()
            OptionRow("Quick Access Settings…") { close(); AppModel.shared.openSettings(.files) }
            OptionRow("Hide Quick Access Panel") { close(); settings.v.showFiles = false }
        }
        .padding(8)
        .frame(width: 280)
    }
}

private struct OptionRow: View {
    let title: String
    var checked = false
    var shortcut: String?
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    init(_ title: String, checked: Bool = false, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.checked = checked; self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: fs(11), weight: .semibold)).frame(width: 14).opacity(checked ? 1 : 0)
            Text(title).font(.system(size: fs(13)))
            Spacer()
            if let shortcut { Text(shortcut).font(.system(size: fs(12))).foregroundStyle(hovering.value ? Color.white.opacity(0.85) : .secondary) }
        }
        .foregroundStyle(hovering.value ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering.value ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture(perform: action)
    }
}

private struct OptionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: fs(12), weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
    }
}

private struct OptionDivider: View {
    var body: some View { Divider().padding(.horizontal, 8).padding(.vertical, 4) }
}

/// The preview area of a card: text excerpt, link cover, colour, picture or file thumbnail.
struct ClipPreview: View {
    let clip: Clip

    var body: some View { preview(clip.category) }

    @ViewBuilder private func preview(_ cat: Category) -> some View {
        GeometryReader { geo in
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
                Text(clip.text ?? "")
                    .font(.system(size: fs(12.5))).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
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
        Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip) }
        if let first = clip.fileURLs.first {
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
                        Image(systemName: cat.symbol).font(.system(size: fs(11), weight: .semibold))
                        Text(cat.label).font(.system(size: fs(13), weight: .semibold))
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
                Text(footer(cat)).font(.system(size: fs(10.5))).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
        .onTapGesture {
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
            .contentShape(Circle()).onTapGesture(perform: action)
    }

    private var host: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host?.replacingOccurrences(of: "www.", with: "") ?? t
    }

    private func footer(_ cat: Category) -> String {
        switch cat {
        case .text: return "\((clip.text ?? "").count) characters"
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
    /// Takes in a clipboard item dragged from Drawer's own cards or rows; anything else is ignored.
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
