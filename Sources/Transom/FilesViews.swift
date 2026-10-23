import SwiftUI
import AppKit
// The Quick Access column of the drawer: tiles and list rows, the right-click menu and the options popover.

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
        .accessibleTap(url.lastPathComponent, hint: "Opens the file") { NSWorkspace.shared.open(url) }
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
        .accessibleTap(url.lastPathComponent, hint: "Opens the file") { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { fileMenu(path: path, store: store) }
    }
}

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
                Image(systemName: "photo").font(.system(size: 9)).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(FileIconSize.allCases.firstIndex(of: v.filesIconSize) ?? 1) },
                    set: { settings.v.filesIconSize = FileIconSize.allCases[min(2, max(0, Int($0.rounded())))] }
                ), in: 0...2, step: 1)
                Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 4)
            OptionDivider()
            OptionRow("Quick Access Settings…") { close(); AppModel.shared.openSettings(.files) }
            OptionRow("Hide Quick Access Panel") { close(); settings.v.showFiles = false }
        }
        .padding(6)
        .frame(width: 236)
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
            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).frame(width: 12).opacity(checked ? 1 : 0)
            Text(title).font(.system(size: 13))
            Spacer()
            if let shortcut { Text(shortcut).font(.system(size: 12)).foregroundStyle(hovering.value ? Color.white.opacity(0.85) : .secondary) }
        }
        .foregroundStyle(hovering.value ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(hovering.value ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .accessibleTap(title, selected: checked, action)
    }
}

private struct OptionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 1)
    }
}

private struct OptionDivider: View {
    var body: some View { Divider().padding(.horizontal, 8).padding(.vertical, 3) }
}
