import Foundation

@MainActor
enum PhraseMapStore {
    static let builtInMap: [String: String] = [
        "indus gaming": "Indus Gaming",
        "in this gaming": "Indus Gaming",
        "end this gaming": "Indus Gaming"
    ]

    static func mergedMap(settings: SettingsModel) -> [String: String] {
        var merged: [String: String] = [:]
        merge(into: &merged, from: builtInMap)
        if !settings.postProcessorJSONPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merge(into: &merged, from: loadJSONMap(path: settings.postProcessorJSONPath))
        }
        merge(into: &merged, from: settings.postProcessorReplacements)
        merge(into: &merged, from: settings.phraseMap)
        return merged
    }

    static func contextualStrings(settings: SettingsModel) -> [String] {
        let merged = mergedMap(settings: settings)
        let values = merged.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var deduped: [String: String] = [:]
        for value in values {
            let key = value.lowercased()
            if deduped[key] == nil {
                deduped[key] = value
            }
        }
        let sorted = deduped.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if sorted.count > 50 {
            return Array(sorted.prefix(50))
        }
        return sorted
    }

    private static func merge(into target: inout [String: String], from source: [String: String]) {
        for (key, value) in source {
            let normalizedKey = normalizeKey(key)
            guard !normalizedKey.isEmpty else { continue }
            target[normalizedKey] = value
        }
    }

    private static func loadJSONMap(path: String) -> [String: String] {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return [:] }
        let url = URL(fileURLWithPath: trimmedPath)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func normalizeKey(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ").lowercased()
    }
}
