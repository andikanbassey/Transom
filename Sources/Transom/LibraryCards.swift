import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The cards of the Library and the right-click menu for a clipboard item there.

/// A Craft-style card: a coloured frame that fades toward the bottom, around a soft white card. On hover the white
/// card grows outward over the frame until the stroke is gone; it settles back when the pointer leaves.
struct LibraryCard<Preview: View>: View {
    let frame: Color
    let title: String
    let symbol: String
    let meta: String
    var appIcon: NSImage?
    var tint: Color?
    /// A sensitive item's removal time: the card shows the countdown next to the details.
    var expiry: Date?
    @ViewBuilder var preview: () -> Preview
    @StateObject private var hovering = Box(false)
    private let outerRadius: CGFloat = 18
    private let stroke: CGFloat = 5

    var body: some View {
        let inset = hovering.value ? 0 : stroke
        ZStack {
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(LinearGradient(colors: [frame.opacity(0.9), frame.opacity(0.5), frame.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            // The content is laid out once, at the card's full size, and only the clip shape changes with hover.
            // Nothing inside reflows or moves, so the text stays still while the card grows over the stroke.
            inner
                .mask(
                    RoundedRectangle(cornerRadius: outerRadius - inset, style: .continuous)
                        .padding(inset)
                )
        }
        .shadow(color: .black.opacity(hovering.value ? 0.13 : 0.07), radius: hovering.value ? 12 : 8, y: hovering.value ? 5 : 3)
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .animation(.easeInOut(duration: 0.28), value: hovering.value)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint ?? frame)
                        Text(meta).font(Look.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        if let expiry { SensitiveClock(expiry: expiry) }
                    }
                }
                Spacer(minLength: 6)
                if let appIcon {
                    Image(nsImage: appIcon).resizable().aspectRatio(contentMode: .fit).frame(width: 38, height: 38)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            Rectangle().fill(Look.hairline).frame(height: 1).padding(.horizontal, 14)
            preview().clipped()
        }
        .background(Look.card)
    }
}

/// A clipboard item in the Library: click copies it, drag takes it into another app.
struct LibraryClipCard: View {
    let clip: Clip
    let store: ClipboardStore
    @StateObject private var copied = Box(false)

    var body: some View {
        let cat = clip.category
        LibraryCard(frame: cat.tint, title: clip.title, symbol: clip.kindSymbol,
                    meta: "\(clip.kindLabel) · \(clip.date.formatted(.relative(presentation: .named)))",
                    appIcon: AppIcons.icon(clip.sourceBundleID), tint: cat.tint, expiry: clip.sensitiveExpiry) {
            ClipPreview(clip: clip).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if copied.value {
                Text("Copied").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(.black.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if clip.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(cat.tint, in: Circle()).offset(x: 4, y: -4)
            }
        }
        .accessibleTap(hint: "Copies the item") {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip; return }
            store.copy(clip)
            if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
            withAnimation(.easeOut(duration: 0.15)) { copied.value = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { copied.value = false } }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { LibraryClipMenu(clip: clip, store: store) }
    }
}

/// Right-click menu for a clipboard item in the Library: only things you can do with the item itself.
struct LibraryClipMenu: View {
    let clip: Clip
    let store: ClipboardStore

    var body: some View {
        let cat = clip.category
        let file = clip.sensitive ? nil : (clip.imageURL ?? clip.fileURLs.first)
        // Grouped the way Craft groups its menus: use it, open it, send it somewhere, then pin and delete last.
        Button {
            store.copy(clip)
            if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
        } label: { Label(cat == .image || cat == .gif ? "Copy Image" : "Copy", systemImage: "doc.on.doc") }
        Button { store.expanded = clip } label: { Label("Open in Full", systemImage: "arrow.up.left.and.arrow.down.right") }
        Divider()
        switch cat {
        case .image, .gif:
            if let url = file {
                Button { Self.open(url, withBundleID: "com.apple.Preview") } label: { Label("Open in Preview", systemImage: "eye") }
                Button { Self.save(url) } label: { Label("Save Image As…", systemImage: "square.and.arrow.down") }
            }
        case .video, .audio:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label(cat == .video ? "Play" : "Play Audio", systemImage: "play") } }
        case .pdf:
            if let url = file { Button { Self.open(url, withBundleID: "com.apple.Preview") } label: { Label("Open in Preview", systemImage: "eye") } }
        case .folder:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label("Open Folder", systemImage: "folder") } }
        case .file:
            if let url = file { Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") } }
        case .link:
            if let t = clip.text?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: t) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open Link", systemImage: "safari") }
            }
        case .text, .color:
            EmptyView()
        }
        if !clip.sensitive, let url = clip.fileURLs.first ?? clip.imageURL {
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
        }
        if !clip.sensitive {
            Menu {
                Button { AppModel.shared.notes.addClip(clip) } label: { Label("Notes", systemImage: "note.text") }
                Button { AppModel.shared.files.addClip(clip) } label: { Label("Quick Access", systemImage: "folder") }
            } label: { Label("Save To", systemImage: "tray.and.arrow.down") }
            if let url = clip.imageURL ?? clip.fileURLs.first {
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            } else if let text = clip.text, !text.isEmpty {
                ShareLink(item: text) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Button { store.togglePin(clip) } label: { Label(clip.pinned ? "Unpin" : "Pin", systemImage: clip.pinned ? "pin.slash" : "pin") }
        }
        SensitiveToggleButton(clip: clip, store: store, library: true)
        Divider()
        Button(role: .destructive) { store.delete(clip) } label: { Label("Delete", systemImage: "trash") }
    }

    private static func open(_ url: URL, withBundleID id: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { NSWorkspace.shared.open(url); return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }
}
