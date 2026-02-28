import Foundation

@MainActor
struct TextPostProcessor {
    static func process(_ raw: String, settings: SettingsModel) -> String {
        var output = normalizeWhitespace(raw)

        if settings.spokenPunctuationEnabled {
            output = applySpokenPunctuation(to: output)
        }

        if settings.phraseMapEnabled {
            output = applyPhraseMap(to: output, settings: settings)
        }

        if settings.smartPunctuationEnabled {
            output = applySmartPunctuation(to: output, minWords: settings.minWordsForAutoPeriod)
        }

        output = finalCleanup(output)
        return output
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let normalized = normalizeWhitespacePreservingNewlines(text)
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySpokenPunctuation(to text: String) -> String {
        let commands: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("question mark", "?"),
            ("exclamation point", "!"),
            ("exclamation mark", "!"),
            ("full stop", "."),
            ("semicolon", ";"),
            ("colon", ":"),
            ("comma", ","),
            ("period", "."),
            ("dash", " - ")
        ]

        var output = text
        for (phrase, replacement) in commands {
            output = replaceCaseInsensitivePhrase(in: output, phrase: phrase, replacement: replacement)
        }
        return output
    }

    private static func applyPhraseMap(to text: String, settings: SettingsModel) -> String {
        let replacements = PhraseMapStore.mergedMap(settings: settings)
        guard !replacements.isEmpty else { return text }
        let orderedKeys = replacements.keys.sorted { $0.count > $1.count }
        var output = text
        for key in orderedKeys {
            guard let replacement = replacements[key] else { continue }
            output = replaceCaseInsensitivePhrase(in: output, phrase: key, replacement: replacement)
        }
        return output
    }

    private static func applySmartPunctuation(to text: String, minWords: Int) -> String {
        var output = trimTrailingSpacesAndTabs(text)
        let endsWithNewline = output.hasSuffix("\n")
        let terminalCheck = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let endsWithTerminal = terminalCheck.last.map { ".?!".contains($0) } ?? false
        let wordCount = output.split(whereSeparator: { $0.isWhitespace }).count

        if !endsWithNewline && !endsWithTerminal && wordCount >= max(1, minWords) {
            output.append(".")
        }

        if let first = output.first, first.isLetter {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }

        return output
    }

    private static func finalCleanup(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "[ \t]+([,\\.\\?\\!\\:\\;])",
                                             with: "$1",
                                             options: .regularExpression)
        output = output.replacingOccurrences(of: "([,\\.\\?\\!\\:\\;])(?=[A-Za-z0-9])",
                                             with: "$1 ",
                                             options: .regularExpression)
        output = output.replacingOccurrences(of: "[ \t]*-[ \t]*",
                                             with: " - ",
                                             options: .regularExpression)
        output = normalizeWhitespacePreservingNewlines(output)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceCaseInsensitivePhrase(in text: String, phrase: String, replacement: String) -> String {
        let tokens = phrase.split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !tokens.isEmpty else { return text }
        let pattern = "(?i)\\b" + tokens.joined(separator: "\\s+") + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func normalizeWhitespacePreservingNewlines(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let cleanedLines = lines.map { line -> String in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return parts.joined(separator: " ")
        }
        return cleanedLines.joined(separator: "\n")
    }

    private static func trimTrailingSpacesAndTabs(_ text: String) -> String {
        var output = text
        while let last = output.last, last == " " || last == "\t" {
            output.removeLast()
        }
        return output
    }
}
