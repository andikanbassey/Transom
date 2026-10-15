import AppKit
import Combine
import Carbon.HIToolbox

struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }

    init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }

    init?(appURL: URL) {
        guard let id = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        bundleID = id
        name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum CaptureMode: String, Codable, CaseIterable {
    case all, allowOnly, blockList
    var label: String {
        switch self {
        case .all: "All apps"
        case .allowOnly: "Only allowed"
        case .blockList: "All except blocked"
        }
    }
}

enum Appearance: String, Codable, CaseIterable {
    case system, dark, light
    var label: String { rawValue.capitalized }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

enum Mod: String, Codable, CaseIterable {
    case command, option, control, shift
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
    var label: String { "\(symbol) \(rawValue.capitalized)" }
}

/// How long unpinned clipboard items are kept.
enum Retention: Int, Codable, CaseIterable {
    case day, week, month, year, forever
    var label: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .forever: "Forever"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .year: 365 * 86_400
        case .forever: nil
        }
    }
}

enum PasteMode: String, Codable { case activeApp, clipboard, expand }
enum ScrollZone: String, Codable, CaseIterable {
    case menuBar, topEdge
    var label: String { self == .menuBar ? "Anywhere on the menu bar" : "Only the top edge" }
}
enum ItemsStyle: String, Codable, CaseIterable {
    case cards, lists, custom
    var label: String { rawValue.capitalized }
}
enum NotesOpen: String, Codable { case lastView, list }
enum FileSort: String, Codable, CaseIterable {
    case name, kind, dateAdded, dateModified
    var label: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .dateAdded: "Date Added"
        case .dateModified: "Date Modified"
        }
    }
}
enum FilesView: String, Codable, CaseIterable {
    case icons, list
    var label: String { self == .icons ? "Icons" : "List" }
}
enum FileIconSize: String, Codable, CaseIterable {
    case small, medium, large
    var label: String { rawValue.capitalized }
}
enum FilesMode: String, Codable { case reference, folder }

struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String

    init(keyCode: UInt32, carbonModifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.carbonModifiers = carbonModifiers; self.label = label
    }

    init(event: NSEvent) {
        let f = event.modifierFlags
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = m
        switch Int(event.keyCode) {
        case kVK_Space: label = "Space"
        case kVK_Return: label = "↩"
        case kVK_Tab: label = "⇥"
        case kVK_LeftArrow: label = "←"
        case kVK_RightArrow: label = "→"
        case kVK_UpArrow: label = "↑"
        case kVK_DownArrow: label = "↓"
        default:
            let c = event.charactersIgnoringModifiers?.uppercased() ?? ""
            label = (c.unicodeScalars.first.map { $0.value < 0xF700 } ?? false) && !c.isEmpty ? c : "Key \(event.keyCode)"
        }
    }

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + label
    }
}

struct SettingsValues: Codable, Equatable {
    var onboarded = false

    /// Panels in display order, with any missing from the saved order added at the end.
    var orderedPanels: [Panel] {
        var o: [Panel] = []
        for p in panelOrder where !o.contains(p) { o.append(p) }
        for p in Panel.allCases where !o.contains(p) { o.append(p) }
        return o
    }
    /// The drawer never gets shorter than its content needs; cards need a little more than rows.
    var minimumHeight: Double { clipboardCards ? 270 : 200 }
    var activeHeight: Double {
        get { max(minimumHeight, drawerHeight) }
        set { drawerHeight = newValue }
    }
    var defaultActiveHeight: Double { 300 }
    func isShown(_ p: Panel) -> Bool {
        switch p { case .clipboard: showClipboard; case .files: showFiles; case .notes: showNotes }
    }
    /// Panel widths. Cards want a wide clipboard (3 : 1 : 1); with the clipboard as a list the three panels are equal
    /// (1 : 1 : 1). Each layout keeps its own sizes, so dragging a divider in one does not disturb the other.
    func weight(_ p: Panel) -> Double { max(0.2, (clipboardCards ? panelWeights : panelWeightsList)[p.rawValue] ?? 1) }
    mutating func setWeight(_ p: Panel, _ w: Double) {
        if clipboardCards { panelWeights[p.rawValue] = w } else { panelWeightsList[p.rawValue] = w }
    }

    // Opening the drawer
    var scrollOpen = true
    /// Where scrolling down opens the drawer: anywhere along the menu bar, or only the very top edge of the screen.
    var scrollZone: ScrollZone = .menuBar
    var holdOpen = false
    var holdModifier = Mod.command
    var waitOpen = false
    var waitDelay = 0.5
    var hotkeyEnabled = true
    var hotkey = HotKeySpec(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey), label: "V")
    /// Natural-scrolling is set per device in macOS, so mouse and trackpad are inverted separately.
    var invertMouseScroll = false
    var invertTrackpadScroll = false
    /// Seconds after the pointer leaves before the drawer closes itself. 0 means only a click closes it.
    var autoHideSeconds = 0.0

    // Panels
    var showClipboard = true
    var showFiles = true
    var showNotes = true
    /// Left-to-right order of the panels, and each panel's share of the width.
    var panelOrder: [Panel] = [.files, .clipboard, .notes]
    /// Clipboard takes three fifths of the width, files and notes one fifth each.
    var panelWeights: [String: Double] = ["clipboard": 3, "files": 1, "notes": 1]
    var panelWeightsList: [String: Double] = ["clipboard": 1, "files": 1, "notes": 1]
    /// Set once the layout defaults above have been applied to settings saved by older builds.
    var layoutV2 = false
    /// Clipboard items as a strip of cards (true) or a list of rows (false).
    var clipboardCards = true
    var notesCards = true
    var filesCards = true
    /// Cards or lists for everything at once, or "custom" to choose clipboard, notes and files separately.
    var itemsMode = ItemsStyle.cards

    // Clipboard
    var paused = false
    var retention = Retention.month
    var pasteMode = PasteMode.activeApp
    var quickPaste = true
    var quickPasteModifier = Mod.command
    var sounds = true

    // Privacy
    var ignoreConfidential = true
    var ignoreTransient = true
    var linkPreviews = true
    var showDuringScreenSharing = true
    var captureMode = CaptureMode.all
    var allowedApps: [AppRef] = []
    var blockedApps: [AppRef] = []

    // Look
    var appearance = Appearance.dark
    var translucency = 0.6
    var liquidGlass = true
    var drawerHeight = 300.0
    var showMenuBarIcon = true
    /// Looks for a new release on GitHub about once a day. Nothing is installed without a click.
    var checkForUpdates = true

    // Automation: drawer:// links and AppleScript. Off until the user turns it on.
    var automationEnabled = false
    /// Apps that may copy or paste through Drawer without being asked each time.
    var automationTrusted: [AppRef] = []

    // Storage. nil means the app's own folder.
    var notesFolder: String?
    var clipboardFolder: String?
    var filesMode = FilesMode.reference
    var filesFolder: String?

    // Files panel view
    var filesSort = FileSort.dateAdded
    var filesFoldersOnTop = true
    var filesView = FilesView.icons
    var filesIconSize = FileIconSize.medium

    // Notes panel
    var notesOpenWith = NotesOpen.lastView
    var notesShowingList = true
    var lastNoteFile: String?
    var notesFontSize = 13.0
}

final class Settings: ObservableObject {
    static let shared = Settings()
    @Published var v: SettingsValues { didSet { save() } }
    private let file = supportDir.appendingPathComponent("settings.json")

    private init() {
        // Merge saved values over the defaults so settings written by older builds keep working
        // when new fields appear.
        v = SettingsValues()
        guard let saved = try? Data(contentsOf: file),
              let savedObj = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defaults = try? JSONEncoder().encode(SettingsValues()),
              var merged = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any] else { return }
        merged.merge(savedObj) { _, new in new }
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let decoded = try? JSONDecoder().decode(SettingsValues.self, from: data) {
            v = decoded
            // The old single "invert scroll" switch was set against a mouse, so carry it over to the mouse.
            if (savedObj["reverseScroll"] as? Bool) == true, savedObj["invertMouseScroll"] == nil { v.invertMouseScroll = true }
        }
        // Settings from before the new default layout (files, clipboard at three fifths, notes) move to it once.
        if !v.layoutV2 {
            v.panelOrder = SettingsValues().panelOrder
            v.panelWeights = SettingsValues().panelWeights
            v.drawerHeight = SettingsValues().drawerHeight
            v.layoutV2 = true
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(v) { try? data.write(to: file, options: .atomic) }
    }

    /// Whether a copy from this app should be recorded.
    func allows(bundleID: String?) -> Bool {
        switch v.captureMode {
        case .all: return true
        case .allowOnly: return bundleID.map { id in v.allowedApps.contains { $0.bundleID == id } } ?? false
        case .blockList: return bundleID.map { id in !v.blockedApps.contains { $0.bundleID == id } } ?? true
        }
    }

    func block(_ app: AppRef) {
        guard !v.blockedApps.contains(app) else { return }
        v.blockedApps.append(app)
    }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs, present when iCloud Drive is on.
    static var iCloudDrive: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - Global hotkey

/// Carbon hotkeys work without any permission prompt.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var action: () -> Void = {}
    private var ref: EventHotKeyRef?
    private var current: HotKeySpec?
    private var handlerInstalled = false

    func register(_ spec: HotKeySpec?) {
        guard spec != current else { return }
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        current = spec
        guard let spec else { return }
        if !handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyCenter.shared.action() }
                return noErr
            }, 1, &type, nil, nil)
            handlerInstalled = true
        }
        RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, EventHotKeyID(signature: 0x4452_5752, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Pasting into the frontmost app

enum Paster {
    /// Posting key events needs the Accessibility permission.
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pasteNow() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
