import Foundation

final class PostProcessor {
    struct Rule: Codable {
        let find: String
        let replace: String
        let caseSensitive: Bool
    }

    struct Store: Codable {
        let version: Int
        let rules: [Rule]
    }

    private let rules: [Rule]
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        let (url, store) = Self.loadStore(fileManager: fileManager)
        self.fileURL = url
        self.rules = store.rules
    }

    var contextualStrings: [String] {
        Array(Set(rules.map { $0.replace })).sorted()
    }

    func process(_ text: String) -> String {
        let normalized = normalizeWhitespace(in: text)
        guard !rules.isEmpty else { return normalized }
        return rules.reduce(normalized) { partial, rule in
            apply(rule: rule, to: partial)
        }
    }

    private func normalizeWhitespace(in text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func apply(rule: Rule, to text: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rule.find))\\b"
        let options: NSRegularExpression.Options = rule.caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: rule.replace)
    }

    private static func loadStore(fileManager: FileManager) -> (URL?, Store) {
        guard let url = replacementsFileURL(fileManager: fileManager) else {
            return (nil, defaultStore())
        }

        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            return (url, store)
        }

        let store = defaultStore()
        if !fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: url.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(store) {
                try? data.write(to: url, options: [.atomic])
            }
        }

        return (url, store)
    }

    private static func replacementsFileURL(fileManager: FileManager) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Dicta/Transcription/replacements.json")
    }

    private static func defaultStore() -> Store {
        Store(version: 1, rules: [])
    }
}
