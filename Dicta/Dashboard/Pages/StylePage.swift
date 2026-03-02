import SwiftUI

struct StylePage: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var showingEditor = false
    @State private var editorProfile = StyleProfile(name: "New Style")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Style Profiles")
                    .font(.title2)
                Spacer()
                Button("Add") {
                    editorProfile = StyleProfile(name: "New Style")
                    showingEditor = true
                }
            }

            List {
                ForEach(store.styleProfiles) { profile in
                    row(for: profile)
                }
                .onDelete(perform: delete)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingEditor) {
            StyleEditor(profile: editorProfile) { updated in
                if store.styleProfiles.contains(where: { $0.id == updated.id }) {
                    store.updateStyleProfile(updated)
                } else {
                    store.addStyleProfile(updated)
                }
            }
        }
    }

    private func row(for profile: StyleProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Button("Edit") {
                    editorProfile = profile
                    showingEditor = true
                }
            }
            Text(profile.appBundleIDs.isEmpty ? "Default (all apps)" : profile.appBundleIDs.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contextMenu {
            Button("Edit") {
                editorProfile = profile
                showingEditor = true
            }
            Button("Delete", role: .destructive) {
                store.deleteStyleProfile(id: profile.id)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { store.styleProfiles[safe: $0]?.id }
        for id in ids {
            store.deleteStyleProfile(id: id)
        }
    }
}

private struct StyleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var appBundleIDsText: String
    @State private var smartPunctuationEnabled: Bool
    @State private var spokenPunctuationEnabled: Bool
    @State private var phraseMapEnabled: Bool
    @State private var casingMode: StyleProfile.CasingMode
    @State private var dashStyle: StyleProfile.DashStyle
    private let id: UUID
    private let createdAt: Date
    private let onSave: (StyleProfile) -> Void

    init(profile: StyleProfile, onSave: @escaping (StyleProfile) -> Void) {
        _name = State(initialValue: profile.name)
        _appBundleIDsText = State(initialValue: profile.appBundleIDs.joined(separator: ", "))
        _smartPunctuationEnabled = State(initialValue: profile.smartPunctuationEnabled)
        _spokenPunctuationEnabled = State(initialValue: profile.spokenPunctuationEnabled)
        _phraseMapEnabled = State(initialValue: profile.phraseMapEnabled)
        _casingMode = State(initialValue: profile.casingMode)
        _dashStyle = State(initialValue: profile.dashStyle)
        self.id = profile.id
        self.createdAt = profile.createdAt
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Style Profile")
                .font(.title2)
            TextField("Name", text: $name)
            TextField("App Bundle IDs (comma separated)", text: $appBundleIDsText)

            Toggle("Smart punctuation", isOn: $smartPunctuationEnabled)
            Toggle("Spoken punctuation", isOn: $spokenPunctuationEnabled)
            Toggle("Phrase map", isOn: $phraseMapEnabled)

            Picker("Casing", selection: $casingMode) {
                ForEach(StyleProfile.CasingMode.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }

            Picker("Dash style", selection: $dashStyle) {
                ForEach(StyleProfile.DashStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let appIDs = appBundleIDsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let profile = StyleProfile(id: id,
                                               name: name,
                                               appBundleIDs: appIDs,
                                               smartPunctuationEnabled: smartPunctuationEnabled,
                                               spokenPunctuationEnabled: spokenPunctuationEnabled,
                                               phraseMapEnabled: phraseMapEnabled,
                                               casingMode: casingMode,
                                               dashStyle: dashStyle,
                                               createdAt: createdAt,
                                               updatedAt: Date())
                    onSave(profile)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
