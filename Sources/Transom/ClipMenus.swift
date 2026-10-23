import SwiftUI
import AppKit
// What you can do with a clipboard item: the right-click menus, marking sensitive, clearing unpinned items, and dragging out.

/// Right-click menu shared by clipboard rows and cards.
struct ClipMenu: View {
    let clip: Clip
    let store: ClipboardStore
    var body: some View {
        Button("Open in Full") { store.expanded = clip }
        Button("Paste") { AppModel.shared.use(clip, paste: true) }
        Divider()
        if !clip.sensitive { Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip) } }
        SensitiveToggleButton(clip: clip, store: store)
        if !clip.sensitive, let first = clip.fileURLs.first {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first]) }
        }
        if let id = clip.sourceBundleID, let name = clip.sourceApp {
            Button("Never Record from \(name)") {
                Settings.shared.block(AppRef(bundleID: id, name: name))
                Settings.shared.v.captureMode = .blockList
            }
        }
        Button("Delete") { store.delete(clip) }
        Divider()
        AppMenuItems()
    }
}

/// What gets dragged out of a card or row into another app: the text, the image, or the file itself.
extension View {
    /// Takes in a clipboard item dragged from Transom's own cards or rows; anything else is ignored.
    func clipDrop(targeted: Binding<Bool>, perform: @escaping (Clip) -> Void) -> some View {
        onDrop(of: [.item], isTargeted: targeted) { _ in
            guard let clip = AppModel.shared.takeDragged() else { return false }
            perform(clip)
            Haptics.drop()
            return true
        }
    }
}

func dragProvider(_ clip: Clip) -> NSItemProvider {
    AppModel.shared.beginDrag(clip)
    switch clip.kind {
    case .text:
        return NSItemProvider(object: (clip.text ?? "") as NSString)
    case .image:
        if let url = clip.imageURL, let p = NSItemProvider(contentsOf: url) { return p }
    case .file:
        if let url = clip.fileURLs.first, let p = NSItemProvider(contentsOf: url) { return p }
    }
    return NSItemProvider(object: clip.title as NSString)
}

/// Right-click item that marks a clipboard item sensitive (masked, memory only, removed after a countdown) or undoes it.
struct SensitiveToggleButton: View {
    let clip: Clip
    let store: ClipboardStore
    var library = false
    var body: some View {
        if clip.sensitive {
            if library {
                Button { store.unmarkSensitive(clip) } label: { Label("Not Sensitive", systemImage: "lock.open") }
            } else {
                Button("Not Sensitive") { store.unmarkSensitive(clip) }
            }
        } else if library {
            Button { store.markSensitive(clip) } label: { Label("Mark as Sensitive", systemImage: "lock") }
        } else {
            Button("Mark as Sensitive") { store.markSensitive(clip) }
        }
    }
}

/// "Clear Unpinned" that follows the filters: with Claude chosen in the app filter it clears only Claude's unpinned items.
struct ClearUnpinnedButton: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        let n = store.unpinnedShown.count
        if let scope = store.clearScopeName {
            // Asked inside the window: a system alert takes focus away and the drawer closes on that.
            Button(scope == "this selection" ? "Clear Unpinned Items Shown (\(n))…" : "Clear Unpinned from \(scope) (\(n))…") {
                store.pendingClear = .init(scope: scope, count: n)
            }
            .disabled(n == 0)
        } else {
            Button("Clear All Unpinned Items") { store.clearUnpinned() }
        }
    }
}

/// The yes/no for a filtered "Clear Unpinned", shown at the bottom of the clipboard panel so the drawer stays open.
struct ClearConfirmBar: View {
    @ObservedObject var store: ClipboardStore
    var body: some View {
        if let pending = store.pendingClear {
            let what = pending.scope == "this selection" ? "the unpinned items shown" : "unpinned items from \(pending.scope)"
            HStack(spacing: 10) {
                Text("Clear \(pending.count) \(pending.count == 1 ? "item" : "items") (\(what))?")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Button("Cancel") { withAnimation { store.pendingClear = nil } }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12, weight: .medium))
                Button("Clear") {
                    store.clearUnpinnedShown()
                    withAnimation { store.pendingClear = nil }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 4).background(Color.red, in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .padding(.horizontal, 14).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: store.appFilter) { _, _ in store.pendingClear = nil }
            .onChange(of: store.filter) { _, _ in store.pendingClear = nil }
            .onChange(of: store.time) { _, _ in store.pendingClear = nil }
        }
    }
}
