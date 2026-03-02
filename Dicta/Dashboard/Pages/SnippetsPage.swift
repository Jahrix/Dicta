import SwiftUI
import AppKit

struct SnippetsPage: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var query = ""
    @State private var showingEditor = false
    @State private var editorSnippet = Snippet(title: "", content: "")

    private var filteredSnippets: [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.snippets }
        return store.snippets.filter { snippet in
            snippet.title.localizedCaseInsensitiveContains(trimmed) ||
            snippet.content.localizedCaseInsensitiveContains(trimmed) ||
            snippet.tags.joined(separator: ",").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            List {
                ForEach(filteredSnippets) { snippet in
                    row(for: snippet)
                }
                .onDelete(perform: delete)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingEditor) {
            SnippetEditor(snippet: editorSnippet) { updated in
                if store.snippets.contains(where: { $0.id == updated.id }) {
                    store.updateSnippet(updated)
                } else {
                    store.addSnippet(title: updated.title, content: updated.content, tags: updated.tags)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Snippets")
                .font(.title2)
            Spacer()
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Button("Add") {
                editorSnippet = Snippet(title: "", content: "")
                showingEditor = true
            }
        }
    }

    private func row(for snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title)
                    .font(.headline)
                Text(snippet.content)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if !snippet.tags.isEmpty {
                    Text(snippet.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snippet.content, forType: .string)
            }
            Button("Edit") {
                editorSnippet = snippet
                showingEditor = true
            }
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snippet.content, forType: .string)
            }
            Button("Edit") {
                editorSnippet = snippet
                showingEditor = true
            }
            Button("Delete", role: .destructive) {
                store.deleteSnippet(id: snippet.id)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { filteredSnippets[safe: $0]?.id }
        for id in ids {
            store.deleteSnippet(id: id)
        }
    }
}

private struct SnippetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String
    @State private var tagsText: String
    private let id: UUID
    private let createdAt: Date
    private let onSave: (Snippet) -> Void

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void) {
        _title = State(initialValue: snippet.title)
        _content = State(initialValue: snippet.content)
        _tagsText = State(initialValue: snippet.tags.joined(separator: ", "))
        self.id = snippet.id
        self.createdAt = snippet.createdAt
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snippet")
                .font(.title2)
            TextField("Title", text: $title)
            TextEditor(text: $content)
                .frame(height: 120)
                .border(Color.secondary.opacity(0.3))
            TextField("Tags (comma separated)", text: $tagsText)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let snippet = Snippet(id: id,
                                          title: title,
                                          content: content,
                                          tags: tags,
                                          createdAt: createdAt,
                                          updatedAt: Date())
                    onSave(snippet)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 260)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
