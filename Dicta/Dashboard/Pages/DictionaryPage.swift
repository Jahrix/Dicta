import SwiftUI

struct DictionaryPage: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var query = ""
    @State private var showingEditor = false
    @State private var editorEntry = DictionaryEntry(spoken: "", replacement: "")

    private var filteredEntries: [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.dictionaryEntries }
        return store.dictionaryEntries.filter { entry in
            entry.spoken.localizedCaseInsensitiveContains(trimmed) ||
            entry.replacement.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            List {
                ForEach(filteredEntries) { entry in
                    row(for: entry)
                }
                .onDelete(perform: delete)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingEditor) {
            DictionaryEditor(entry: editorEntry) { updated in
                if store.dictionaryEntries.contains(where: { $0.id == updated.id }) {
                    store.updateDictionaryEntry(updated)
                } else {
                    store.addDictionaryEntry(spoken: updated.spoken,
                                              replacement: updated.replacement,
                                              enabled: updated.enabled)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Dictionary")
                .font(.title2)
            Spacer()
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Button("Add") {
                editorEntry = DictionaryEntry(spoken: "", replacement: "")
                showingEditor = true
            }
        }
    }

    private func row(for entry: DictionaryEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                store.setDictionaryEntryEnabled(id: entry.id, enabled: !entry.enabled)
            } label: {
                Image(systemName: entry.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(entry.enabled ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.spoken)
                    .font(.headline)
                Text("→ \(entry.replacement)")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Edit") {
                editorEntry = entry
                showingEditor = true
            }
        }
        .contextMenu {
            Button("Edit") {
                editorEntry = entry
                showingEditor = true
            }
            Button("Delete", role: .destructive) {
                store.deleteDictionaryEntry(id: entry.id)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { filteredEntries[safe: $0]?.id }
        for id in ids {
            store.deleteDictionaryEntry(id: id)
        }
    }
}

private struct DictionaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spoken: String
    @State private var replacement: String
    @State private var enabled: Bool
    private let id: UUID
    private let createdAt: Date
    private let onSave: (DictionaryEntry) -> Void

    init(entry: DictionaryEntry, onSave: @escaping (DictionaryEntry) -> Void) {
        _spoken = State(initialValue: entry.spoken)
        _replacement = State(initialValue: entry.replacement)
        _enabled = State(initialValue: entry.enabled)
        self.id = entry.id
        self.createdAt = entry.createdAt
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary Entry")
                .font(.title2)
            TextField("Spoken phrase", text: $spoken)
            TextField("Replacement", text: $replacement)
            Toggle("Enabled", isOn: $enabled)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let entry = DictionaryEntry(id: id,
                                                spoken: spoken,
                                                replacement: replacement,
                                                enabled: enabled,
                                                createdAt: createdAt,
                                                updatedAt: Date())
                    onSave(entry)
                    dismiss()
                }
                .disabled(spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
