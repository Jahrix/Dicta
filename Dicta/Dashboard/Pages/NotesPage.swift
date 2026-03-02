import SwiftUI

struct NotesPage: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedNoteID: UUID?
    @State private var draftTitle: String = ""
    @State private var draftBody: String = ""

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedNoteID) {
                ForEach(store.notes) { note in
                    VStack(alignment: .leading) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.body)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }
                    .tag(note.id)
                }
                .onDelete(perform: delete)
            }
            .frame(minWidth: 220)

            Divider()

            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .onChange(of: selectedNoteID) { _ in
            syncDraft()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Note") {
                    let title = "New Note"
                    store.addNote(title: title, body: "")
                    selectedNoteID = store.notes.last?.id
                    syncDraft()
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedNoteID == nil {
                Text("Select a note")
                    .foregroundColor(.secondary)
            } else {
                TextField("Title", text: $draftTitle)
                    .font(.title2)
                TextEditor(text: $draftBody)
                    .border(Color.secondary.opacity(0.2))
            }
        }
        .padding(12)
        .onChange(of: draftTitle) { _ in
            commitDraft()
        }
        .onChange(of: draftBody) { _ in
            commitDraft()
        }
    }

    private func syncDraft() {
        guard let note = selectedNote else {
            draftTitle = ""
            draftBody = ""
            return
        }
        draftTitle = note.title
        draftBody = note.body
    }

    private func commitDraft() {
        guard var note = selectedNote else { return }
        note.title = draftTitle
        note.body = draftBody
        store.updateNote(note)
    }

    private var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return store.notes.first { $0.id == id }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { store.notes[safe: $0]?.id }
        for id in ids {
            store.deleteNote(id: id)
        }
        if let first = store.notes.first {
            selectedNoteID = first.id
        } else {
            selectedNoteID = nil
        }
        syncDraft()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
