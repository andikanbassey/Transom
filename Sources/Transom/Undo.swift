import SwiftUI

/// "Deleted 3 items · Undo" at the bottom of the clipboard panel (and the Library) for a few seconds after a delete.
struct UndoToast: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        ZStack {
            if let pending = store.undoable, store.pendingClear == nil, store.pendingDelete == nil, store.naming == nil {
                let n = pending.clips.count
                HStack(spacing: 12) {
                    Image(systemName: "trash").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                    Text(n == 1 ? "Deleted “\(pending.clips[0].title.prefix(40))”" : "Deleted \(n) items")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    Button("Undo") { withAnimation(.easeOut(duration: 0.2)) { store.undoDelete() } }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                        .keyboardShortcut("z", modifiers: .command)
                        .accessibilityHint("Brings back what was just deleted")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(pending.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.undoable)
    }
}
