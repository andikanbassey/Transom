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
        case .files: "Quick Access"
        default: rawValue.capitalized
        }
    }
    var blurb: String {
        switch self {
        case .general: "Startup, sounds and your data."
        case .clipboard: "How long items are kept and how they paste."
        case .files: "How pinned files are stored and shown."
        case .notes: "Where notes live and how they open."
        case .panels: "Choose what appears in Transom."
        case .privacy: "Control what Transom is allowed to remember."
        case .shortcuts: "Open and close Transom your way."
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
    @Published var pane = Pane(rawValue: Env["PANE"] ?? "") ?? .general
}

// MARK: - Shared helpers

// MARK: - Window

struct SettingsView: View {
    @ObservedObject private var pane = SettingsNav.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var captureLog = CaptureLog.shared
    @StateObject private var showLicense = Box(false)

    private static let groups: [(String, [Pane])] = [
        ("Transom", [.general, .panels, .shortcuts, .appearance]),
        ("Content", [.clipboard, .files, .notes]),
        ("Data", [.privacy, .storage, .advanced]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                PageHeader(title: pane.pane.title, subtitle: pane.pane.blurb) { EmptyView() }
                    .padding(.horizontal, 32).padding(.top, 58).padding(.bottom, Look.headerGap)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) { content }
                        .padding(.horizontal, 32).padding(.bottom, 36)
                }
            }
            .background(Look.page)
            .sheet(isPresented: Binding(get: { showLicense.value }, set: { showLicense.value = $0 })) {
                LicenseSheet { showLicense.value = false }
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    /// The same sidebar as the Library's: brand, quiet group headers, rows, and the Library/Settings switch at the bottom.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarBrand()
            ForEach(Self.groups, id: \.0) { group in
                SidebarHeader(title: group.0)
                ForEach(group.1) { p in
                    SidebarRow(title: p.title, symbol: p.symbol, color: p.color, selected: pane.pane == p)
                        .accessibleTap(p.title, selected: pane.pane == p) { pane.pane = p }
                }
            }
            Spacer()
            ModeSwitch()
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: Look.sidebarWidth)
        .background(Look.sidebar)
    }

    private func bind<T>(_ kp: WritableKeyPath<SettingsValues, T>) -> Binding<T> {
        Binding(get: { settings.v[keyPath: kp] }, set: { settings.v[keyPath: kp] = $0 })
    }

    private func cardsOrList(_ kp: WritableKeyPath<SettingsValues, Bool>) -> some View {
        Picker("", selection: bind(kp)) {
            Text("Cards").tag(true)
            Text("List").tag(false)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
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
            Row("Show menu bar icon", subtitle: "If hidden, open Transom again from Applications to get back here.") { toggle(\.showMenuBarIcon) }
            RowDivider()
            Row("Check for updates", subtitle: "Looks for a new version on GitHub about once a day. Nothing installs until you say so.") { toggle(\.checkForUpdates) }
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
            Row("Data folder", subtitle: supportDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Button("Show in Finder") { NSWorkspace.shared.open(supportDir) }
            }
        }
        Section("About \(Brand.name)") {
            Row("\(Brand.name) \(Brand.version)", subtitle: "A clipboard history, quick notes and pinned files in a window that opens at the top of your screen. Everything stays on your Mac.") { EmptyView() }
            RowDivider()
            Row("Why “Transom”?", subtitle: "A transom is the small window above a door: open it a little and you can see through without opening the door.") { EmptyView() }
            RowDivider()
            UpdateRow()
            RowDivider()
            Row("Source code", subtitle: "github.com/andikanbassey/Transom") {
                Button("Open on GitHub") { NSWorkspace.shared.open(Brand.repoURL) }
            }
            RowDivider()
            Row("Report a problem or suggest a feature", subtitle: "Bugs and ideas are tracked on GitHub.") {
                Button("Open Issues") { NSWorkspace.shared.open(Brand.issuesURL) }
            }
            RowDivider()
            Row("Privacy", subtitle: "No accounts and no analytics. What you copy never leaves your Mac, except in the iCloud Drive folders you choose to sync. The only other request is the update check to GitHub.") { EmptyView() }
            RowDivider()
            Row("License", subtitle: "MIT License. Free to use, copy and modify.") {
                Button("View License…") { showLicense.value = true }
            }
            RowDivider()
            Row("Third-party software", subtitle: "None. Transom is built only with Apple's frameworks (AppKit and SwiftUI).") { EmptyView() }
            RowDivider()
            Row("Made by Andikan Bassey", subtitle: Brand.copyright) { EmptyView() }
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
            Row("Pause capture", subtitle: "Stop recording new clipboard items.") { toggle(\.paused) }
        }
        Section("Storage") {
            FolderRow(title: "Clipboard folder", subtitle: "One Markdown file per month. Pictures copied from the screen are kept in an Images folder inside it; copied files stay where they are.",
                      path: settings.v.clipboardFolder, defaultURL: supportDir.appendingPathComponent("Clipboard"),
                      iCloudSub: "Transom/Clipboard") { settings.v.clipboardFolder = $0 }
            if settings.v.clipboardFolder != nil {
                RowDivider()
                Row("Keep pictures on this Mac", subtitle: "Copied pictures can be large. When this is on they stay out of the synced folder and don't use iCloud storage; your other Macs keep the text and links but not the pictures. Clearing history deletes the pictures either way.") {
                    Toggle("", isOn: Binding(get: { settings.v.picturesStayOnThisMac },
                                             set: { settings.v.picturesStayOnThisMac = $0; ClipboardFolder.relocatePictures(toLocal: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
        }
        Section("Paste items") {
            Row("Clicking an item") {
                Picker("", selection: bind(\.pasteMode)) {
                    Text("Pastes into the app").tag(PasteMode.activeApp)
                    Text("Only copies").tag(PasteMode.clipboard)
                    Text("Opens it in full").tag(PasteMode.expand)
                }
                .labelsHidden().frame(width: 190)
            }
            if settings.v.pasteMode != .clipboard { RowDivider(); AccessibilityRow() }
            RowDivider()
            Row("Quick paste", subtitle: "Press the modifier with 1–9 while Transom is open.") {
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
                FolderRow(title: "Quick Access folder", subtitle: "Dropped files are copied here.", path: settings.v.filesFolder,
                          defaultURL: supportDir.appendingPathComponent("Files"), iCloudSub: "Transom/Files") { settings.v.filesFolder = $0 }
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
                      defaultURL: supportDir.appendingPathComponent("Notes"), iCloudSub: "Transom/Notes") { settings.v.notesFolder = $0 }
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
        Section("Show in Transom") {
            Row("Clipboard", subtitle: "History of everything you copy.") { toggle(\.showClipboard) }
            RowDivider()
            Row("Quick Access", subtitle: "Pinned files and folders, one click away.") { toggle(\.showFiles) }
            RowDivider()
            Row("Notes", subtitle: "Quick notes for numbers, links and tasks.") { toggle(\.showNotes) }
        }
        Section("Order") {
            PanelPad()
            RowDivider()
            Row("Sizes", subtitle: "Drag a panel above to move it. Drag a divider to resize panels, or the bottom edge to change the height.") {
                Button("Reset Sizes") {
                    settings.v.panelWeights = SettingsValues().panelWeights
                    settings.v.panelWeightsList = SettingsValues().panelWeightsList
                    settings.v.drawerHeight = 300
                }
            }
        }
    }

    @ViewBuilder private var privacy: some View {
        Section("Clipboard content") {
            Row("Keep sensitive items, masked", subtitle: "Passwords from password managers and secret keys stay in the list as scrambled text you can still copy or paste. They are kept in memory only, never saved or synced, and removed after 15 minutes.") { toggle(\.keepSensitiveMasked) }
            RowDivider()
            Row("Ignore confidential content", subtitle: "Don't record passwords and other data apps flag as concealed, when sensitive items are not kept.") { toggle(\.ignoreConfidential) }
            RowDivider()
            Row("Ignore transient content", subtitle: "Don't save temporary data generated by other apps.") { toggle(\.ignoreTransient) }
            RowDivider()
            Row("Generate link previews", subtitle: "Downloads the page for a title and image. May trigger one-time or analytics-sensitive links.") { toggle(\.linkPreviews) }
            RowDivider()
            Row("Show during screen sharing", subtitle: "Let Transom appear to others when you share your screen.") { toggle(\.showDuringScreenSharing) }
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
        Section("Open Transom") {
            Row("Scroll down at the top of the screen", subtitle: "Swipe up over the top of Transom to close it.") { toggle(\.scrollOpen) }
            RowDivider()
            Row("Where scrolling opens it", subtitle: "With the menu bar showing, scrolling anywhere along it opens Transom. A hidden menu bar only reacts at the very top edge.") {
                Picker("", selection: bind(\.scrollZone)) {
                    ForEach(ScrollZone.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 200).disabled(!settings.v.scrollOpen)
            }
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
            Row("Close Transom", subtitle: "Clicking outside always closes it. This also closes it on its own after the pointer has left.") {
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
        Section("Items") {
            Row("Show everything as", subtitle: "Cards show a preview; lists are compact. Custom chooses for each. Transom's files and notes keep their own layout.") {
                Picker("", selection: Binding(get: { settings.v.itemsMode }, set: { mode in
                    settings.v.itemsMode = mode
                    switch mode {
                    case .cards: settings.v.clipboardCards = true; settings.v.notesCards = true; settings.v.filesCards = true
                    case .lists: settings.v.clipboardCards = false; settings.v.notesCards = false; settings.v.filesCards = false
                        settings.v.filesView = .list
                    case .custom: break
                    }
                })) {
                    ForEach(ItemsStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            if settings.v.itemsMode == .custom {
                RowDivider()
                Row("Clipboard") { cardsOrList(\.clipboardCards) }
                RowDivider()
                Row("Notes") { cardsOrList(\.notesCards) }
                RowDivider()
                Row("Quick Access") { cardsOrList(\.filesCards) }
            }
        }
        Section("Look") {
            Row("Theme") {
                Picker("", selection: bind(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            if #available(macOS 26.0, *) {
                RowDivider()
                Row("Liquid Glass", subtitle: "Use the system glass material for Transom.") { toggle(\.liquidGlass) }
            }
            RowDivider()
            Row("Background opacity", subtitle: "Lower values let the wallpaper show through.") {
                HStack {
                    Slider(value: bind(\.translucency), in: 0.2...1.0).frame(width: 160)
                    Text("\(Int(settings.v.translucency * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                }
            }
            RowDivider()
            Row("Height") {
                HStack {
                    Slider(value: bind(\.activeHeight), in: settings.v.minimumHeight...700).frame(width: 160)
                    Text("\(Int(settings.v.activeHeight))").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                }
            }
        }
    }

    @ViewBuilder private var storage: some View {
        Section("iCloud Drive") {
            Row("Keep notes, files and clipboard history in iCloud Drive",
                subtitle: Settings.iCloudDrive == nil ? "iCloud Drive isn't available on this Mac." : "macOS syncs the folders between your Macs. Folders are set in the Clipboard, Files and Notes panes.") {
                ICloudToggle()
            }
        }
    }

    @ViewBuilder private var advanced: some View {
        Section("Scroll direction") {
            Row("Invert for third-party mice", subtitle: "For wheel mice from Logitech, Razer and others. Turn on if scrolling at the top edge feels backwards with a mouse.") { toggle(\.invertMouseScroll) }
            RowDivider()
            Row("Invert for Apple trackpad and Magic Mouse", subtitle: "Applies to devices that report touch gestures. Separate from the setting above.") { toggle(\.invertTrackpadScroll) }
        }
        Section("Automation") {
            Row("Allow automation", subtitle: "Let other apps and scripts control Transom with transom:// links and AppleScript. Off by default.") { toggle(\.automationEnabled) }
            if settings.v.automationEnabled {
                RowDivider()
                Row("Trusted apps", subtitle: settings.v.automationTrusted.isEmpty
                    ? "No app is trusted yet. The first time an app asks to copy or paste, you will be asked."
                    : "These apps can copy and paste through Transom without asking.") { EmptyView() }
                ForEach(settings.v.automationTrusted) { app in
                    RowDivider()
                    Row(app.name, subtitle: app.bundleID) {
                        Button("Remove") { settings.v.automationTrusted.removeAll { $0.bundleID == app.bundleID } }
                    }
                }
                RowDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Examples").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Text("open \"transom://open\"\nopen \"transom://search?q=invoice\"\nopen \"transom://pause\"\nopen \"transom://paste?index=1&plain=1\"\nosascript -e 'tell application \"Transom\" to get clip text 1'")
                        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Item 1 is the newest. Links that only change Transom always work once this is on; copying and pasting need a trusted app. Clipboard content can be read out only with AppleScript.")
                        .font(Look.meta).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
        Section("Capture log") {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Transom saw on the clipboard and what it did with it. Useful if something you copied did not show up.")
                    .font(Look.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if captureLog.entries.isEmpty {
                    Text("Nothing copied yet this session.").font(Look.meta).foregroundStyle(.tertiary)
                } else {
                    ForEach(captureLog.entries.prefix(12)) { e in
                        Text(e.line).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(captureLog.entries.map(\.line).joined(separator: "\n"), forType: .string)
                    }
                    Button("Clear") { captureLog.clear() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        Section("Setup") {
            Row("Welcome screen", subtitle: "Run the first-launch setup again.") {
                Button("Show Welcome…") { AppModel.shared.showOnboarding() }
            }
        }
    }
}

// MARK: - Building blocks

