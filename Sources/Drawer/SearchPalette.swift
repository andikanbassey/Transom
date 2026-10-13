import SwiftUI
import AppKit

/// One row in the global search.
private struct PaletteItem: Identifiable {
    let id: String
    let section: String
    let symbol: String
    var tint: Color = .secondary
    let title: String
    var subtitle: String = ""
    var hint: String = ""
    var thumb: URL?
    var keepsOpen = false
    let run: () -> Void
}

/// Global search and jump: clipboard items, notes, files and app actions in one list, driven from the keyboard.
struct SearchPalette: View {
    /// The open search is exactly as wide as the field it opens from.
    static let width: CGFloat = 340
    @ObservedObject var nav = MainNav.shared
    @ObservedObject var clipboard = AppModel.shared.clipboard
    @ObservedObject var notes = AppModel.shared.notes
    @ObservedObject var files = AppModel.shared.files
    @StateObject private var query = Box("")
    @StateObject private var selected = Box(0)
    @FocusState private var focused: Bool

    var body: some View {
        let items = results()
        VStack(spacing: 8) {
            // The field and the results are one unit: the results drop straight down from the field, at its width.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField(nav.placeholder, text: $query.value)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { run(items) }
                    .onChange(of: query.value) { _, _ in selected.value = 0 }
            }
            .padding(.horizontal, 12)
            .frame(width: SearchPalette.width, height: 34)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if items.isEmpty {
                            Text("No results").font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 26)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if i == 0 || items[i - 1].section != item.section {
                                Text(item.section).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 20).padding(.top, i == 0 ? 6 : 14).padding(.bottom, 5)
                            }
                            row(item, on: i == selected.value)
                                .id(item.id)
                                .onTapGesture { selected.value = i; run(items) }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selected.value) { _, i in
                    if items.indices.contains(i) { proxy.scrollTo(items[i].id) }
                }
            }
            .frame(width: SearchPalette.width)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
        }
        .onAppear {
            focused = true; selected.value = 0
            if let q = nav.pendingQuery { query.value = q; nav.pendingQuery = nil }
        }
        .onKeyPress(.downArrow) { selected.value = min(selected.value + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selected.value = max(selected.value - 1, 0); return .handled }
        .onExitCommand { nav.paletteOpen = false }
    }

    private func row(_ item: PaletteItem, on: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumb = item.thumb {
                    Thumb(url: thumb, size: CGSize(width: 36, height: 36))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                } else {
                    Image(systemName: item.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(item.tint)
                        .frame(width: 36, height: 36)
                        .background(item.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14.5, weight: .medium)).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if on, !item.hint.isEmpty { Text(item.hint).font(.system(size: 12)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(on ? Look.selection : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    private func run(_ items: [PaletteItem]) {
        guard items.indices.contains(selected.value) else { return }
        let item = items[selected.value]
        if item.keepsOpen { item.run(); return }
        nav.remember(query.value)
        nav.paletteOpen = false
        item.run()
    }

    // MARK: Results

    private func results() -> [PaletteItem] {
        let q = query.value.trimmingCharacters(in: .whitespaces)
        let scope = nav.scope
        var out: [PaletteItem] = []

        func go(_ s: DesktopSection) { nav.tab = .library; nav.section = s; clipboard.expanded = nil
            if s == .notes { notes.showingList = true } }
        func noteItem(_ n: Note) -> PaletteItem {
            PaletteItem(id: "note-\(n.id)", section: "Notes", symbol: "note.text", tint: .yellow, title: n.title,
                        subtitle: n.preview) { nav.tab = .library; nav.section = .notes; notes.select(n) }
        }
        func fileItem(_ p: String) -> PaletteItem {
            let url = URL(fileURLWithPath: p)
            return PaletteItem(id: "file-\(p)", section: "Quick Access", symbol: "doc", tint: .blue, title: url.lastPathComponent,
                               subtitle: url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                               thumb: url) { NSWorkspace.shared.open(url) }
        }
        var actions: [PaletteItem] = DesktopSection.allCases.map { s in
            PaletteItem(id: "go-\(s.rawValue)", section: "Go to", symbol: s.symbol, title: s.title) { go(s) }
        }
        actions.append(PaletteItem(id: "new-note", section: "Actions", symbol: "square.and.pencil", title: "New Note") {
            notes.add(); nav.tab = .library; nav.section = .notes })
        actions.append(PaletteItem(id: "pause", section: "Actions", symbol: Settings.shared.v.paused ? "play.circle" : "pause.circle",
                                   title: Settings.shared.v.paused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") {
            Settings.shared.v.paused.toggle() })
        actions.append(PaletteItem(id: "clear", section: "Actions", symbol: "trash", title: "Clear Unpinned Clipboard") {
            clipboard.clearUnpinned() })
        let panes: [PaletteItem] = Pane.allCases.map { p in
            PaletteItem(id: "pane-\(p.rawValue)", section: "Settings", symbol: "gearshape", title: p.title,
                        subtitle: p.blurb) { SettingsNav.shared.pane = p; nav.tab = .settings }
        }

        let recents = nav.recents.map { r in
            PaletteItem(id: "recent-\(r)", section: "Earlier", symbol: "magnifyingglass", title: r, keepsOpen: true) { query.value = r }
        }
        let matchClips = clipboard.clips.filter { $0.title.localizedCaseInsensitiveContains(q) || ($0.text ?? "").localizedCaseInsensitiveContains(q)
            || ($0.sourceApp ?? "").localizedCaseInsensitiveContains(q) }
        let matchNotes = notes.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
        let matchFiles = files.paths.filter { URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveContains(q) }

        // The page you are on decides what is searched: clipboard page, clipboard only; settings, settings only.
        switch scope {
        case .clipboard:
            out += q.isEmpty ? recents + clipboard.visible.prefix(6).map(clipItem) : matchClips.prefix(8).map(clipItem)
        case .notes:
            out += q.isEmpty ? recents + notes.notes.prefix(6).map(noteItem) : matchNotes.prefix(8).map(noteItem)
        case .files:
            out += q.isEmpty ? recents + files.paths.prefix(6).map(fileItem) : matchFiles.prefix(8).map(fileItem)
        case .settings:
            out += q.isEmpty ? panes : panes.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q) }
        case .all:
            if q.isEmpty {
                out += recents
                out += actions.filter { $0.section == "Go to" || $0.id == "new-note" }
                out += clipboard.visible.prefix(4).map(clipItem)
            } else {
                out += matchClips.prefix(6).map(clipItem)
                out += matchNotes.prefix(4).map(noteItem)
                out += matchFiles.prefix(4).map(fileItem)
                out += (actions + panes).filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(6)
            }
        }
        return out
    }

    private func clipItem(_ c: Clip) -> PaletteItem {
        let cat = c.category
        let thumb: URL? = [.image, .gif, .video, .pdf].contains(cat) ? c.previewURL : nil
        return PaletteItem(id: "clip-\(c.id)", section: "Clipboard", symbol: cat.symbol, tint: cat.tint, title: c.title,
                           subtitle: [cat.label, c.sourceApp, c.date.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "),
                           hint: "Copy", thumb: thumb) {
            clipboard.copy(c)
            if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
        }
    }
}

/// The search field in each page header. Click it, or press ⌘K: the search opens from this corner and grows to the left.
struct SearchBarButton: View {
    @ObservedObject var nav = MainNav.shared
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
            Text(nav.placeholder).font(.system(size: 13.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text("⌘K").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(width: SearchPalette.width, height: 34)
        .background(Look.card.opacity(hovering.value ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onTapGesture { nav.paletteOpen = true }
        .anchorPreference(key: SearchAnchorKey.self, value: .bounds) { $0 }
    }
}

/// Where the search field sits, so the open search can be drawn over the whole window from that spot.
struct SearchAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}
