import AppKit

/// What other apps and scripts can ask Transom to do, through transom:// links (drawer:// still works) and AppleScript.
enum AutomationAction {
    case open, close, pause, resume, togglePause
    case search(String), newNote(String), pin(Int)
    case copy(Int, plain: Bool), paste(Int, plain: Bool)

    /// Copying and pasting reach outside Transom, so the sender has to be trusted. Everything else only changes Transom.
    var actsOutside: Bool {
        switch self { case .copy, .paste: true; default: false }
    }
}

enum AutomationError: LocalizedError {
    case disabled, notAllowed, noItem(Int), bad(String)
    var errorDescription: String? {
        switch self {
        case .disabled: "Automation is turned off. Turn it on in Transom › Settings › Advanced › Automation."
        case .notAllowed: "Transom did not allow this app to copy or paste."
        case .noItem(let i): "There is no clipboard item number \(i)."
        case .bad(let why): why
        }
    }
}

/// Who sent a request, as far as macOS can tell.
struct AutomationSource {
    var bundleID: String?
    var name: String?

    init(pid: pid_t?) {
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            bundleID = app.bundleIdentifier
            name = app.localizedName
        }
    }
    static let unknown = AutomationSource(pid: nil)
}

/// The one place automation requests are checked and carried out.
///
/// Rules: off unless the user turns it on; links and scripts that only change Transom always work once it is on;
/// copying or pasting for another app needs that app to be trusted (asked the first time); clipboard content is only
/// ever read out through AppleScript, never through a link.
final class Automation {
    static let shared = Automation()
    private var asking = false

    var enabled: Bool { Settings.shared.v.automationEnabled }

    // MARK: Links

    /// transom://open, close, pause, resume, toggle-pause, search?q=, note?text=, pin?index=, copy?index=&plain=1, paste?index=&plain=1
    static func parse(_ url: URL) -> AutomationAction? {
        guard ["transom", "drawer"].contains(url.scheme?.lowercased() ?? ""), let command = url.host?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let index = Int(value("index") ?? "")
        let plain = value("plain") == "1"
        switch command {
        case "open": return .open
        case "close": return .close
        case "pause": return .pause
        case "resume": return .resume
        case "toggle-pause": return .togglePause
        case "search": return .search(value("q") ?? "")
        case "note": return .newNote(value("text") ?? "")
        case "pin": return index.map { .pin($0) }
        case "copy": return index.map { .copy($0, plain: plain) }
        case "paste": return index.map { .paste($0, plain: plain) }
        default: return nil
        }
    }

    func handle(url: URL, source: AutomationSource) {
        guard enabled else { NSSound.beep(); return }
        guard let action = Self.parse(url) else { NSSound.beep(); return }
        do { try perform(action, source: source) } catch { NSSound.beep() }
    }

    // MARK: Doing it

    @discardableResult
    func perform(_ action: AutomationAction, source: AutomationSource) throws -> Bool {
        guard enabled else { throw AutomationError.disabled }
        if action.actsOutside { try authorize(source) }
        let model = AppModel.shared
        switch action {
        case .open: model.showDrawer()
        case .close: model.hideDrawer()
        case .pause: Settings.shared.v.paused = true
        case .resume: Settings.shared.v.paused = false
        case .togglePause: Settings.shared.v.paused.toggle()
        case .search(let q):
            SettingsWindow.shared.show(tab: .library)
            MainNav.shared.section = .clipboard
            MainNav.shared.pendingQuery = q
            MainNav.shared.paletteOpen = true
        case .newNote(let text):
            model.notes.add()
            if let id = model.notes.selectedID { model.notes.binding(for: id).wrappedValue = text }
        case .pin(let i):
            let clip = try item(i)
            if !clip.pinned { model.clipboard.togglePin(clip) }
        case .copy(let i, let plain):
            model.clipboard.copy(try item(i), plain: plain)
        case .paste(let i, let plain):
            let clip = try item(i)
            // Paste into whatever is in front right now.
            if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
                model.previousApp = front
            }
            model.use(clip, paste: true, plain: plain)
        }
        return true
    }

    /// Item 1 is the newest.
    func item(_ index: Int) throws -> Clip {
        let clips = AppModel.shared.clipboard.clips
        guard index >= 1, index <= clips.count else { throw AutomationError.noItem(index) }
        return clips[index - 1]
    }

    // MARK: Trust

    private func authorize(_ source: AutomationSource) throws {
        if source.bundleID == Bundle.main.bundleIdentifier { return }
        if let id = source.bundleID, Settings.shared.v.automationTrusted.contains(where: { $0.bundleID == id }) { return }
        guard !asking else { throw AutomationError.notAllowed }
        asking = true
        defer { asking = false }
        let who = source.name ?? "An app Transom can't identify"
        let alert = NSAlert()
        alert.messageText = "Allow “\(who)” to copy or paste with Transom?"
        alert.informativeText = "It asked Transom to put an item on the clipboard or paste it into the app in front. Only allow apps you trust."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow Once")
        if source.bundleID != nil { alert.addButton(withTitle: "Always Allow") }
        alert.addButton(withTitle: "Don't Allow")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let always = source.bundleID != nil
        switch response {
        case .alertFirstButtonReturn: return
        case .alertSecondButtonReturn where always:
            if let id = source.bundleID { Settings.shared.v.automationTrusted.append(AppRef(bundleID: id, name: who)) }
        default: throw AutomationError.notAllowed
        }
    }
}
