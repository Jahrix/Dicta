import Foundation

final class PostProcessor {
    private static let builtInReplacements: [String: String] = [
        "indus gaming": "Indus Gaming",
        "in this gaming": "Indus Gaming",
        "end this gaming": "Indus Gaming"
    ]

    var contextualStrings: [String] {
        let replacements = Self.loadReplacements()
        return Array(Set(replacements.values)).sorted()
    }

    func process(_ text: String, logger: DiagnosticsLogger) -> String {
        logger.log(.transcription, "Raw transcript: \(text)", verbose: true)
        var processed = Self.normalizeWhitespace(text)

        let replacements = Self.loadReplacements()
        if !replacements.isEmpty {
            processed = Self.applyReplacements(to: processed, replacements: replacements)
        }

        processed = Self.normalizeWhitespace(processed)
        logger.log(.transcription, "Processed transcript: \(processed)", verbose: true)
        return processed
    }

    private static func loadReplacements() -> [String: String] {
        var merged: [String: String] = [:]

        for (key, value) in builtInReplacements {
            merged[normalizeKey(key)] = value
        }

        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: SettingsModel.Keys.postProcessorJSONPath),
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: path)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in json {
                    merged[normalizeKey(key)] = value
                }
            }
        }

        if let data = defaults.data(forKey: SettingsModel.Keys.postProcessorReplacements),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in map {
                merged[normalizeKey(key)] = value
            }
        }

        return merged
    }

    private static func applyReplacements(to text: String, replacements: [String: String]) -> String {
        let ordered = replacements.keys.sorted { $0.count > $1.count }
        var output = text
        for key in ordered {
            guard let replacement = replacements[key] else { continue }
            output = replaceCaseInsensitive(in: output, phrase: key, replacement: replacement)
        }
        return output
    }

    private static func replaceCaseInsensitive(in text: String, phrase: String, replacement: String) -> String {
        let tokens = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        let pattern = "(?i)\\b" + tokens.joined(separator: "\\s+") + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private static func normalizeKey(_ text: String) -> String {
        normalizeWhitespace(text).lowercased()
    }
}
