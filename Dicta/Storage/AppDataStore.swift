import Foundation
import Combine

struct AppData: Codable, Equatable {
    var schemaVersion: Int
    var dictionaryEntries: [DictionaryEntry]
    var snippets: [Snippet]
    var styleProfiles: [StyleProfile]
    var notes: [Note]
    var lastUpdatedAt: Date

    init(schemaVersion: Int = 1,
         dictionaryEntries: [DictionaryEntry] = [],
         snippets: [Snippet] = [],
         styleProfiles: [StyleProfile] = [],
         notes: [Note] = [],
         lastUpdatedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.dictionaryEntries = dictionaryEntries
        self.snippets = snippets
        self.styleProfiles = styleProfiles
        self.notes = notes
        self.lastUpdatedAt = lastUpdatedAt
    }
}

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var dictionaryEntries: [DictionaryEntry]
    @Published private(set) var snippets: [Snippet]
    @Published private(set) var styleProfiles: [StyleProfile]
    @Published private(set) var notes: [Note]

    private let store: AppDataStoring
    private var saveTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64

    init(store: AppDataStoring? = nil, debounceSeconds: Double = 0.45) {
        if let store {
            self.store = store
        } else {
            self.store = (try? JSONStore()) ?? InMemoryStore()
        }
        self.debounceNanoseconds = UInt64(max(0.3, min(0.6, debounceSeconds)) * 1_000_000_000)

        let data = (try? self.store.load()) ?? AppData()
        self.dictionaryEntries = data.dictionaryEntries
        self.snippets = data.snippets
        self.styleProfiles = data.styleProfiles
        self.notes = data.notes
    }

    func reload() {
        let data = (try? store.load()) ?? AppData()
        dictionaryEntries = data.dictionaryEntries
        snippets = data.snippets
        styleProfiles = data.styleProfiles
        notes = data.notes
    }

    func addDictionaryEntry(spoken: String, replacement: String, enabled: Bool = true) {
        let entry = DictionaryEntry(spoken: spoken, replacement: replacement, enabled: enabled)
        dictionaryEntries.append(entry)
        scheduleSave()
    }

    func updateDictionaryEntry(_ entry: DictionaryEntry) {
        guard let index = dictionaryEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        dictionaryEntries[index] = updated
        scheduleSave()
    }

    func setDictionaryEntryEnabled(id: UUID, enabled: Bool) {
        guard let index = dictionaryEntries.firstIndex(where: { $0.id == id }) else { return }
        dictionaryEntries[index].enabled = enabled
        dictionaryEntries[index].updatedAt = Date()
        scheduleSave()
    }

    func deleteDictionaryEntry(id: UUID) {
        dictionaryEntries.removeAll { $0.id == id }
        scheduleSave()
    }

    func addSnippet(title: String, content: String, tags: [String] = []) {
        let snippet = Snippet(title: title, content: content, tags: tags)
        snippets.append(snippet)
        scheduleSave()
    }

    func updateSnippet(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var updated = snippet
        updated.updatedAt = Date()
        snippets[index] = updated
        scheduleSave()
    }

    func deleteSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        scheduleSave()
    }

    func addStyleProfile(_ profile: StyleProfile) {
        var updated = profile
        updated.updatedAt = Date()
        styleProfiles.append(updated)
        scheduleSave()
    }

    func updateStyleProfile(_ profile: StyleProfile) {
        guard let index = styleProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = Date()
        styleProfiles[index] = updated
        scheduleSave()
    }

    func deleteStyleProfile(id: UUID) {
        styleProfiles.removeAll { $0.id == id }
        scheduleSave()
    }

    func addNote(title: String, body: String) {
        let note = Note(title: title, body: body)
        notes.append(note)
        scheduleSave()
    }

    func updateNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[index] = updated
        scheduleSave()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = snapshotData()
        saveTask = Task { [snapshot, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            do {
                try store.save(snapshot)
            } catch {
                NSLog("AppDataStore save failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveNow() {
        let snapshot = snapshotData()
        do {
            try store.save(snapshot)
        } catch {
            NSLog("AppDataStore save failed: \(error.localizedDescription)")
        }
    }

    private func snapshotData() -> AppData {
        AppData(schemaVersion: 1,
                dictionaryEntries: dictionaryEntries,
                snippets: snippets,
                styleProfiles: styleProfiles,
                notes: notes,
                lastUpdatedAt: Date())
    }
}

private final class InMemoryStore: AppDataStoring {
    private var data = AppData()

    func load() throws -> AppData {
        data
    }

    func save(_ data: AppData) throws {
        self.data = data
    }
}
