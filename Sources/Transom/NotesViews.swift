import SwiftUI
import AppKit
// The Notes column of the drawer: the list of notes and a note's row.

struct NotesColumn: View {
    @ObservedObject var store: NotesStore
    var showsGear: Bool
    @ObservedObject var settings = Settings.shared
    @StateObject private var query = Box("")
    @StateObject private var searching = Box(false)
    @StateObject private var targeted = Box(false)
    @StateObject private var noteController = NoteEditorController()

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Notes") {
                HeaderIcon(symbol: "plus") { store.add() }.help("New note")
                HeaderIcon(symbol: "magnifyingglass", active: searching.value) {
                    searching.value.toggle()
                    if searching.value { store.showingList = true } else { query.value = "" }
                }.help("Search notes")
                HeaderIcon(symbol: "list.bullet", active: store.showingList) { store.showingList.toggle() }.help("All notes")
                PanelMenu {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.folder) }
                    Divider()
                    Button("Notes Settings…") { AppModel.shared.openSettings(.notes) }
                    Button("Hide Notes Panel") { settings.v.showNotes = false }
                }
                if showsGear { HeaderIcon(symbol: "gearshape") { AppModel.shared.openSettings(nil) }.help("Settings") }
            }
            if store.showingList { list } else { editor }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(targeted.value ? 0.8 : 0), lineWidth: 2).padding(6))
        .clipDrop(targeted: $targeted.value) { clip in store.addClip(clip); store.showingList = true }
    }

    @ViewBuilder private var editor: some View {
        if let id = store.selectedID {
            ZStack(alignment: .topLeading) {
                if store.notes.first(where: { $0.id == id })?.text.isEmpty ?? true {
                    Text("Quick notes, phone numbers, tasks…")
                        .font(.system(size: settings.v.notesFontSize)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 19).padding(.top, 8)
                }
                // The same editor as the Library's, so a note with a picture shows the picture here as well.
                MarkdownEditor(text: store.binding(for: id), fontSize: settings.v.notesFontSize, controller: noteController)
                    .padding(.horizontal, 19).padding(.top, 4).padding(.bottom, 10)
                    .id(id)
            }
        }
    }

    private var list: some View {
        let q = query.value.trimmingCharacters(in: .whitespaces)
        let shown = store.notes.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) }
        return VStack(spacing: 6) {
            if searching.value {
                TextField("Search notes", text: $query.value)
                    .textFieldStyle(.plain).font(.system(size: fs(12)))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(shown) { note in NoteRow(note: note, store: store) }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let store: NotesStore
    var inWindow = false
    @StateObject private var hovering = Box(false)
    @StateObject private var confirming = Box(false)

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: fs(13.5), weight: .medium)).lineLimit(1)
                Text(note.preview.isEmpty ? note.date.formatted(date: .abbreviated, time: .omitted) : note.preview)
                    .font(.system(size: fs(12))).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if confirming.value {
                // The first click on the x only asks; this red button is the one that deletes.
                Text("Delete").font(.system(size: fs(11), weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Color.red, in: Capsule())
                    .contentShape(Capsule())
                    .accessibleTap("Confirm delete note", combine: false) { store.delete(note) }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if hovering.value {
                Image(systemName: "xmark").font(.system(size: fs(10), weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .accessibleTap("Delete note", combine: false) {
                        confirming.value = true
                        // Not confirmed in a few seconds: back to the x.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirming.value = false }
                    }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hovering.value || note.id == store.selectedID ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: confirming.value)
        .onHover { hovering.value = $0 }
        .accessibleTap(note.title, selected: note.id == store.selectedID) { store.select(note) }
        .contextMenu {
            NoteMenu(note: note, store: store)
            if !inWindow { Divider(); AppMenuItems() }
        }
    }
}
