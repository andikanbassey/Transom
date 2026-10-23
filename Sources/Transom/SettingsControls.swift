import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// The controls the settings panes are built from: confirmations, the iCloud switch, the shortcut field, sliders and folder rows.

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
            Settings.shared.v.notesFolder = base.appendingPathComponent("Transom/Notes").path
            Settings.shared.v.filesFolder = base.appendingPathComponent("Transom/Files").path
            Settings.shared.v.clipboardFolder = base.appendingPathComponent("Transom/Clipboard").path
            Settings.shared.v.filesMode = .folder
        } else {
            Settings.shared.v.notesFolder = nil
            Settings.shared.v.filesFolder = nil
            Settings.shared.v.clipboardFolder = nil
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
        Row("Accessibility access", subtitle: trusted.value ? "Transom can paste into the app you are using."
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

    /// "iCloud Drive › Transom › Notes" instead of the long Mobile Documents path.
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
            .accessibleTap("Show folder in Finder", hint: friendly) { NSWorkspace.shared.open(URL(fileURLWithPath: current)) }
            .help("Show in Finder")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
