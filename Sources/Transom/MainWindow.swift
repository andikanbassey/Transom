import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

// The window that holds the Library and Settings: navigation, the Library | Settings switch and the sidebar pieces.

final class MainNav: ObservableObject {
    static let shared = MainNav()
    @Published var tab = MainTab.library
    @Published var section = DesktopSection.all
    @Published var paletteOpen = false
    /// A search handed in from outside (transom://search), picked up when the search opens.
    var pendingQuery: String?
    /// The last few things searched for, shown under "Earlier" when the search opens.
    @Published var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    /// What the search looks through: the page you are on decides.
    enum Scope { case all, clipboard, notes, files, settings }
    var scope: Scope {
        if tab == .settings { return .settings }
        switch section {
        case .all: return .all
        case .clipboard, .pinned: return .clipboard
        case .notes: return .notes
        case .files: return .files
        }
    }
    var placeholder: String {
        switch scope {
        case .all: "Search everything"
        case .clipboard: "Search clipboard"
        case .notes: "Search notes"
        case .files: "Search quick access"
        case .settings: "Search settings"
        }
    }

    func remember(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        recents = Array(([q] + recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        UserDefaults.standard.set(recents, forKey: "recentSearches")
    }
}

/// One window for the Library (history, notes, files) and Settings, switched from the sidebar.
/// It sits in the Dock while it is open and goes back to the menu bar when it closes.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private var themeWatcher: AnyCancellable?
    /// For the TRANSOM_THEME_TEST debug aid.
    var appearanceName: String { window?.appearance?.name.rawValue ?? "system" }

    func show(pane: Pane? = nil, tab: MainTab = .settings) {
        if let pane { SettingsNav.shared.pane = pane }
        MainNav.shared.tab = tab
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 620)
            w.contentView = NSHostingView(rootView: MainWindowView())
            w.setFrameAutosaveName("DrawerMainWindow")
            if !w.setFrameUsingName("DrawerMainWindow") { w.center() }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
            window = w
            // The window's own appearance follows the Theme setting live, not just when the window opens.
            themeWatcher = Settings.shared.$v.map(\.appearance).removeDuplicates().sink { [weak self] a in
                self?.window?.appearance = a.nsAppearance
            }
        }
        window?.appearance = Settings.shared.v.appearance.nsAppearance
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainWindowView: View {
    @ObservedObject var nav = MainNav.shared
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if nav.tab == .library { DesktopView() } else { SettingsView() }
            }
        }
        // The open search is drawn here, above a scrim over the whole window, but starting at the header field.
        .overlayPreferenceValue(SearchAnchorKey.self) { anchor in
            GeometryReader { geo in
                if nav.paletteOpen, let anchor {
                    let r = geo[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture { nav.paletteOpen = false }.accessibilityHidden(true)
                        SearchPalette().fixedSize().offset(x: r.maxX - SearchPalette.width, y: r.minY)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.14), value: nav.paletteOpen)
        // Theme applies to the whole window, Library and Settings alike, and follows the setting as it changes.
        .preferredColorScheme(settings.v.appearance == .system ? nil : (settings.v.appearance == .dark ? .dark : .light))
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// A plain row at the bottom of the sidebar ("Settings"), with an optional shortcut hint.
struct SidebarAction: View {
    let title: String
    let symbol: String
    var hint: String?
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26)
            Text(title).font(.system(size: 14))
            Spacer()
            if let hint { Text(hint).font(Look.meta).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(hovering.value ? Color.primary : Color.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(hovering.value ? Look.selection.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .accessibleTap(title, action)
    }
}

/// The two-sided switch at the bottom of both sidebars. The side you are on shows its icon and is bold and coloured;
/// the other is plain grey text of the same size. Both halves are equal, so nothing shifts when you switch.
struct ModeSwitch: View {
    @ObservedObject private var nav = MainNav.shared

    var body: some View {
        HStack(spacing: 2) {
            side("Library", "square.grid.2x2.fill", .library)
            side("Settings", "gearshape.fill", .settings)
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .animation(.easeOut(duration: 0.16), value: nav.tab)
    }

    private func side(_ title: String, _ symbol: String, _ tab: MainTab) -> some View {
        let on = nav.tab == tab
        return HStack(spacing: 6) {
            if on { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
            Text(title).font(.system(size: 13, weight: on ? .semibold : .regular))
        }
        .foregroundStyle(on ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity).frame(height: 30)
        .background(on ? Look.card : .clear, in: Capsule())
        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 2, y: 1)
        .contentShape(Capsule())
        .accessibleTap(title, selected: on) { nav.tab = tab }
    }
}

enum DesktopSection: String, CaseIterable {
    case all, clipboard, pinned, notes, files
    var title: String {
        switch self {
        case .all: "All"
        case .clipboard: "Clipboard"
        case .pinned: "Pinned"
        case .notes: "Notes"
        case .files: "Quick Access"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .pinned: "pin.fill"
        case .notes: "note.text"
        case .files: "folder.fill"
        }
    }
    var color: Color {
        switch self {
        case .all: Color(white: 0.45)
        case .clipboard: Color(red: 0.25, green: 0.50, blue: 0.95)
        case .pinned: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .notes: Color(red: 0.95, green: 0.72, blue: 0.18)
        case .files: Color(red: 0.30, green: 0.62, blue: 0.95)
        }
    }
}

/// Dropping a clipboard card on "Notes" or "Quick Access" in the sidebar keeps it there.
struct SidebarDrop: ViewModifier {
    let section: DesktopSection
    let notes: NotesStore
    let files: FilesStore
    @StateObject private var targeted = Box(false)

    func body(content: Content) -> some View {
        if section == .notes || section == .files {
            content
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(targeted.value ? 0.9 : 0), lineWidth: 2))
                .clipDrop(targeted: $targeted.value) { clip in
                    if section == .notes { notes.addClip(clip) } else { files.addClip(clip) }
                }
        } else {
            content
        }
    }
}
