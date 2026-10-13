import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case general, clipboard, files, notes, panels, privacy, shortcuts, appearance, storage, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .storage: "iCloud & Storage"
        default: rawValue.capitalized
        }
    }
    var blurb: String {
        switch self {
        case .general: "Startup, sounds and your data."
        case .clipboard: "How long items are kept and how they paste."
        case .files: "How pinned files are stored and shown."
        case .notes: "Where notes live and how they open."
        case .panels: "Choose what appears in the drawer."
        case .privacy: "Control what Drawer is allowed to remember."
        case .shortcuts: "Open and close the drawer your way."
        case .appearance: "Theme, glass and size."
        case .storage: "Where notes and files live, and syncing."
        case .advanced: "Fine-tuning and setup."
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .files: "folder.fill"
        case .notes: "note.text"
        case .panels: "rectangle.3.group.fill"
        case .privacy: "hand.raised.fill"
        case .shortcuts: "command"
        case .appearance: "paintbrush.fill"
        case .storage: "icloud.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: Color(white: 0.5)
        case .clipboard: Color(red: 0.25, green: 0.50, blue: 0.95)
        case .files: Color(red: 0.30, green: 0.62, blue: 0.95)
        case .notes: Color(red: 0.95, green: 0.72, blue: 0.18)
        case .panels: Color(red: 0.18, green: 0.62, blue: 0.45)
        case .privacy: Color(red: 0.30, green: 0.45, blue: 0.90)
        case .shortcuts: Color(red: 0.55, green: 0.55, blue: 0.60)
        case .appearance: Color(red: 0.62, green: 0.38, blue: 0.90)
        case .storage: Color(red: 0.30, green: 0.62, blue: 0.95)
        case .advanced: Color(red: 0.90, green: 0.50, blue: 0.20)
        }
    }
}

/// Which settings pane is showing. Shared so the drawer can open a specific pane.
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var pane = Pane(rawValue: ProcessInfo.processInfo.environment["DRAWER_PANE"] ?? "") ?? .general
}

// MARK: - Shared helpers

enum SettingsActions {
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func isInICloud(_ path: String?) -> Bool {
        guard let path, let base = Settings.iCloudDrive?.path else { return false }
        return path.hasPrefix(base)
    }

    static var iCloudEnabled: Bool { isInICloud(Settings.shared.v.notesFolder) }

    /// Keep notes and files in iCloud Drive (synced by macOS), or go back to the app's own folders.
    static func setICloudStorage(_ on: Bool) {
        if on, let base = Settings.iCloudDrive {
            Settings.shared.v.notesFolder = base.appendingPathComponent("Drawer/Notes").path
            Settings.shared.v.filesFolder = base.appendingPathComponent("Drawer/Files").path
            Settings.shared.v.filesMode = .folder
        } else {
            Settings.shared.v.notesFolder = nil
            Settings.shared.v.filesFolder = nil
            Settings.shared.v.filesMode = .reference
        }
    }

    static var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
        )
    }

    static func confirm(_ message: String, detail: String, action: String, perform: () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { perform() }
    }
}

/// Observes settings itself so it always shows the saved state.
struct ICloudToggle: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Toggle("", isOn: Binding(
            get: { SettingsActions.isInICloud(settings.v.notesFolder) },
            set: { SettingsActions.setICloudStorage($0) }
        ))
        .toggleStyle(.switch).labelsHidden().disabled(Settings.iCloudDrive == nil)
    }
}

struct HotKeyField: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var recording = Box(false)
    @StateObject private var monitor = Box<Any?>(nil)

    var body: some View {
        HStack(spacing: 6) {
            Button { recording.value ? stop() : start() } label: {
                Text(recording.value ? "Press shortcut…" : (settings.v.hotkeyEnabled ? settings.v.hotkey.display : "Record Shortcut"))
                    .frame(minWidth: 110)
            }
            if settings.v.hotkeyEnabled && !recording.value {
                Button { settings.v.hotkeyEnabled = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        recording.value = true
        monitor.value = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else { NSSound.beep(); return nil }
            settings.v.hotkey = HotKeySpec(event: e)
            settings.v.hotkeyEnabled = true
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor.value { NSEvent.removeMonitor(m) }
        monitor.value = nil
        recording.value = false
    }
}

struct RetentionSlider: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { Double(settings.v.retention.rawValue) },
                set: { settings.v.retention = Retention(rawValue: Int($0.rounded())) ?? .month }
            ), in: 0...4, step: 1)
            HStack {
                ForEach(Retention.allCases, id: \.self) { r in
                    Text(r.label).font(.system(size: 11))
                        .foregroundStyle(r == settings.v.retention ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct AccessibilityRow: View {
    @StateObject private var trusted = Box(Paster.trusted)
    var body: some View {
        Row("Accessibility access", subtitle: trusted.value ? "Drawer can paste into the app you are using."
                                                            : "Needed to paste straight into other apps. Without it, items are only copied.") {
            if trusted.value {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
            } else {
                Button("Open Settings") { Paster.requestTrust(); Paster.openAccessibilitySettings() }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in trusted.value = Paster.trusted }
    }
}

struct FolderRow: View {
    let title: String
    let subtitle: String
    let path: String?
    let defaultURL: URL
    let iCloudSub: String
    let onChange: (String?) -> Void

    private var current: String { path ?? defaultURL.path }

    /// "iCloud Drive › Drawer › Notes" instead of the long Mobile Documents path.
    private var friendly: String {
        if let base = Settings.iCloudDrive?.path, current.hasPrefix(base) {
            let rest = current.dropFirst(base.count).split(separator: "/").joined(separator: " › ")
            return rest.isEmpty ? "iCloud Drive" : "iCloud Drive › " + rest
        }
        return current.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        let inICloud = SettingsActions.isInICloud(current)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13.5))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if let cloud = Settings.iCloudDrive, !inICloud {
                        Button("iCloud Drive") { onChange(cloud.appendingPathComponent(iCloudSub).path) }
                    }
                    Button("Choose…") { if let url = SettingsActions.chooseFolder() { onChange(url.path) } }
                    if path != nil { Button("Reset") { onChange(nil) } }
                }
                .buttonStyle(PillButtonStyle())
                .layoutPriority(1)
            }
            HStack(spacing: 7) {
                Image(systemName: inICloud ? "icloud.fill" : "folder.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(friendly).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: current)) }
            .help("Show in Finder")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// MARK: - Window

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(pane: Pane? = nil) {
        if let pane { SettingsNav.shared.pane = pane }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var pane = SettingsNav.shared
    @ObservedObject var settings = Settings.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230).background(.ultraThinMaterial)
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.pane.title).font(.system(size: 24, weight: .bold))
                    Text(pane.pane.blurb).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 36).padding(.top, 34).padding(.bottom, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) { content }
                        .padding(.horizontal, 36).padding(.bottom, 36)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 860, height: 620)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Pane.allCases) { p in
                HStack(spacing: 11) {
                    Image(systemName: p.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                    Text(p.title).font(.system(size: 13.5, weight: pane.pane == p ? .semibold : .regular))
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(pane.pane == p ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { pane.pane = p }
            }
            Spacer()
            Text("Drawer 0.4").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 10)
        }
        .padding(.horizontal, 14).padding(.top, 56).padding(.bottom, 16)
    }

    private func bind<T>(_ kp: WritableKeyPath<SettingsValues, T>) -> Binding<T> {
        Binding(get: { settings.v[keyPath: kp] }, set: { settings.v[keyPath: kp] = $0 })
    }

    private func toggle(_ kp: WritableKeyPath<SettingsValues, Bool>) -> some View {
        Toggle("", isOn: bind(kp)).toggleStyle(.switch).labelsHidden()
    }

    @ViewBuilder private var content: some View {
        switch pane.pane {
        case .general: general
        case .clipboard: clipboard
        case .files: files
        case .notes: notes
        case .panels: panels
        case .privacy: privacy
        case .shortcuts: shortcuts
        case .appearance: appearance
        case .storage: storage
        case .advanced: advanced
        }
    }

    // MARK: Panes

    @ViewBuilder private var general: some View {
        Section("App") {
            Row("Open at login") { Toggle("", isOn: SettingsActions.launchAtLogin).toggleStyle(.switch).labelsHidden() }
            RowDivider()
            Row("Show menu bar icon", subtitle: "If hidden, open Drawer again from Applications to get back here.") { toggle(\.showMenuBarIcon) }
            RowDivider()
            Row("Sound effects") { toggle(\.sounds) }
        }
        Section("Data") {
            Row("Erase history", subtitle: "Removes every clipboard item, including pinned ones.") {
                Button("Erase History…") {
                    SettingsActions.confirm("Erase clipboard history?", detail: "This can't be undone.", action: "Erase") {
                        AppModel.shared.clipboard.eraseAll()
                    }
                }
            }
            RowDivider()
            Row("Data folder", subtitle: "Settings and clipboard history are stored here.") {
                Button("Show in Finder") { NSWorkspace.shared.open(supportDir) }
            }
        }
    }

    @ViewBuilder private var clipboard: some View {
        Section("Keep history") {
            VStack(alignment: .leading, spacing: 6) {
                RetentionSlider()
                    .onChange(of: settings.v.retention) { _, _ in AppModel.shared.clipboard.trim() }
                Text("Pinned items are always kept.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            RowDivider()
            Row("Most items to keep", subtitle: "A cap on top of the time limit.") {
                HStack(spacing: 6) {
                    Text("\(settings.v.historyLimit)").monospacedDigit().foregroundStyle(.secondary)
                    Stepper("", value: bind(\.historyLimit), in: 50...5000, step: 50).labelsHidden()
                        .onChange(of: settings.v.historyLimit) { _, _ in AppModel.shared.clipboard.trim() }
                }
            }
            RowDivider()
            Row("Pause capture", subtitle: "Stop recording new clipboard items.") { toggle(\.paused) }
        }
        Section("Paste items") {
            Row("Choosing an item") {
                Picker("", selection: bind(\.pasteMode)) {
                    Text("Pastes into the app").tag(PasteMode.activeApp)
                    Text("Only copies").tag(PasteMode.clipboard)
                }
                .labelsHidden().frame(width: 190)
            }
            if settings.v.pasteMode == .activeApp { RowDivider(); AccessibilityRow() }
            RowDivider()
            Row("Quick paste", subtitle: "Press the modifier with 1–9 while the drawer is open.") {
                HStack(spacing: 8) {
                    Picker("", selection: bind(\.quickPasteModifier)) {
                        ForEach(Mod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 120).disabled(!settings.v.quickPaste)
                    toggle(\.quickPaste)
                }
            }
        }
    }

    @ViewBuilder private var files: some View {
        Section("Pinned files") {
            Row("Storage") {
                Picker("", selection: bind(\.filesMode)) {
                    Text("Reference files in place").tag(FilesMode.reference)
                    Text("Keep copies in a folder").tag(FilesMode.folder)
                }
                .labelsHidden().frame(width: 210)
            }
            if settings.v.filesMode == .folder {
                RowDivider()
                FolderRow(title: "Files folder", subtitle: "Dropped files are copied here.", path: settings.v.filesFolder,
                          defaultURL: supportDir.appendingPathComponent("Files"), iCloudSub: "Drawer/Files") { settings.v.filesFolder = $0 }
            }
        }
        Section("Display") {
            Row("View as") {
                Picker("", selection: bind(\.filesView)) {
                    ForEach(FilesView.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            RowDivider()
            Row("Item size") {
                Picker("", selection: bind(\.filesIconSize)) {
                    ForEach(FileIconSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            RowDivider()
            Row("Arrange by") {
                Picker("", selection: bind(\.filesSort)) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            RowDivider()
            Row("Keep folders on top") { toggle(\.filesFoldersOnTop) }
        }
    }

    @ViewBuilder private var notes: some View {
        Section("Storage") {
            FolderRow(title: "Notes folder", subtitle: "Each note is a Markdown file.", path: settings.v.notesFolder,
                      defaultURL: supportDir.appendingPathComponent("Notes"), iCloudSub: "Drawer/Notes") { settings.v.notesFolder = $0 }
        }
        Section("Display") {
            Row("Open notes with", subtitle: "The list is your front page. “Last view” returns to the note you were editing.") {
                Picker("", selection: bind(\.notesOpenWith)) {
                    Text("Last view").tag(NotesOpen.lastView)
                    Text("Always the list").tag(NotesOpen.list)
                }
                .labelsHidden().frame(width: 160)
            }
            RowDivider()
            Row("Text size") {
                HStack {
                    Slider(value: bind(\.notesFontSize), in: 11...20, step: 1).frame(width: 160)
                    Text("\(Int(settings.v.notesFontSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44)
                }
            }
        }
    }

    @ViewBuilder private var panels: some View {
        Section("Show in the drawer") {
            Row("Clipboard", subtitle: "History of everything you copy.") { toggle(\.showClipboard) }
            RowDivider()
            Row("Files", subtitle: "Pinned files and folders, one click away.") { toggle(\.showFiles) }
            RowDivider()
            Row("Notes", subtitle: "Quick notes for numbers, links and tasks.") { toggle(\.showNotes) }
        }
    }

    @ViewBuilder private var privacy: some View {
        Section("Clipboard content") {
            Row("Ignore confidential content", subtitle: "Don't save passwords and other data apps flag as concealed.") { toggle(\.ignoreConfidential) }
            RowDivider()
            Row("Ignore transient content", subtitle: "Don't save temporary data generated by other apps.") { toggle(\.ignoreTransient) }
            RowDivider()
            Row("Generate link previews", subtitle: "Downloads the page for a title and image. May trigger one-time or analytics-sensitive links.") { toggle(\.linkPreviews) }
            RowDivider()
            Row("Show during screen sharing", subtitle: "Let the drawer appear to others when you share your screen.") { toggle(\.showDuringScreenSharing) }
        }
        Section("Record clipboard from") {
            Row("Apps") {
                Picker("", selection: bind(\.captureMode)) {
                    ForEach(CaptureMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 190)
            }
        }
        AppList(title: "Allow list", note: "Used when apps are set to “Only allowed”.", apps: bind(\.allowedApps), active: settings.v.captureMode == .allowOnly)
        AppList(title: "Block list", note: "Used when apps are set to “All except blocked”.", apps: bind(\.blockedApps), active: settings.v.captureMode == .blockList)
    }

    @ViewBuilder private var shortcuts: some View {
        Section("Open the drawer") {
            Row("Scroll down at the top of the screen", subtitle: "Swipe up over the top of the drawer to close it.") { toggle(\.scrollOpen) }
            RowDivider()
            Row("Hold a key at the top of the screen") {
                HStack(spacing: 8) {
                    Picker("", selection: bind(\.holdModifier)) {
                        ForEach(Mod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 120).disabled(!settings.v.holdOpen)
                    toggle(\.holdOpen)
                }
            }
            RowDivider()
            Row("Wait at the top of the screen") {
                HStack(spacing: 8) {
                    Picker("", selection: bind(\.waitDelay)) {
                        Text("Third of a second").tag(0.3)
                        Text("Half a second").tag(0.5)
                        Text("One second").tag(1.0)
                    }
                    .labelsHidden().frame(width: 150).disabled(!settings.v.waitOpen)
                    toggle(\.waitOpen)
                }
            }
            RowDivider()
            Row("Or just press") { HotKeyField() }
        }
        Section("Closing") {
            Row("Close the drawer", subtitle: "Clicking outside always closes it. This also closes it on its own after the pointer has left.") {
                Picker("", selection: bind(\.autoHideSeconds)) {
                    Text("Only on click").tag(0.0)
                    Text("After 5 seconds").tag(5.0)
                    Text("After 10 seconds").tag(10.0)
                    Text("After 15 seconds").tag(15.0)
                }
                .labelsHidden().frame(width: 160)
            }
        }
    }

    @ViewBuilder private var appearance: some View {
        Section("Look") {
            Row("Theme") {
                Picker("", selection: bind(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            if #available(macOS 26.0, *) {
                RowDivider()
                Row("Liquid Glass", subtitle: "Use the system glass material for the drawer.") { toggle(\.liquidGlass) }
            }
            RowDivider()
            Row("Background opacity", subtitle: "Lower values let the wallpaper show through.") {
                HStack {
                    Slider(value: bind(\.translucency), in: 0.2...1.0).frame(width: 160)
                    Text("\(Int(settings.v.translucency * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                }
            }
            RowDivider()
            Row("Drawer height") {
                HStack {
                    Slider(value: bind(\.drawerHeight), in: 220...480).frame(width: 160)
                    Text("\(Int(settings.v.drawerHeight))").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                }
            }
        }
    }

    @ViewBuilder private var storage: some View {
        Section("iCloud Drive") {
            Row("Keep notes and files in iCloud Drive",
                subtitle: Settings.iCloudDrive == nil ? "iCloud Drive isn't available on this Mac." : "macOS syncs the folders between your Macs. Folders are set in the Files and Notes panes.") {
                ICloudToggle()
            }
        }
        Section("Clipboard history") {
            Row("Sync across Macs", subtitle: "History stays on this Mac for now. On the roadmap.") {
                Text("Coming soon").font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
    }

    @ViewBuilder private var advanced: some View {
        Section("Scroll direction") {
            Row("Invert for mouse", subtitle: "Turn on if opening the drawer feels backwards with a mouse wheel.") { toggle(\.invertMouseScroll) }
            RowDivider()
            Row("Invert for trackpad", subtitle: "Turn on if it feels backwards on a trackpad or Magic Mouse.") { toggle(\.invertTrackpadScroll) }
        }
        Section("Setup") {
            Row("Welcome screen", subtitle: "Run the first-launch setup again.") {
                Button("Show Welcome…") { AppModel.shared.showOnboarding() }
            }
        }
    }
}

// MARK: - Building blocks

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
    }
}

/// Hairline between rows, inset like system lists.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 16) }
}

struct Row<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: () -> Control
    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title; self.subtitle = subtitle; self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control().buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(minHeight: 50)
    }
}

struct AppList: View {
    let title: String
    let note: String
    let apps: Binding<[AppRef]>
    let active: Bool

    var body: some View {
        Section(title) {
            Row(active ? "In use" : "Not in use", subtitle: note) {
                Button("Add App…", action: add)
            }
            ForEach(apps.wrappedValue) { app in
                RowDivider()
                HStack(spacing: 10) {
                    if let icon = AppIcons.icon(app.bundleID) { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name).font(.system(size: 13))
                        Text(app.bundleID).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { apps.wrappedValue.removeAll { $0 == app } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .opacity(active ? 1 : 0.6)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let ref = AppRef(appURL: url), !apps.wrappedValue.contains(ref) { apps.wrappedValue.append(ref) }
        }
    }
}
