import SwiftUI
import AppKit

// The Clipboard column of the drawer: the header with its filters, the card strip and the list, grouped by age.

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
        let visible = store.window
        let hidden = store.hiddenCount
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
                            if hidden > 0 { showOlderCard(hidden, scale: scale) }
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
                            if hidden > 0 { showOlderRow(hidden) }
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
    /// The end of the card strip when older items are held back: one tap draws the next batch.
    fileprivate func showOlderCard(_ hidden: Int, scale: CGFloat) -> some View {
        Button { store.showOlder() } label: {
            VStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: fs(20)))
                Text("Show older").font(.system(size: fs(12), weight: .semibold))
                Text("\(hidden) more").font(.system(size: fs(10.5))).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .frame(width: ClipCard.baseWidth * scale * 0.7)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, 10).padding(.top, 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(min(hidden, ClipboardStore.windowStep)) older items")
    }

    /// The end of the list when older items are held back.
    fileprivate func showOlderRow(_ hidden: Int) -> some View {
        Button { store.showOlder() } label: {
            Text("Show older (\(hidden) more)").font(.system(size: fs(12), weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

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
