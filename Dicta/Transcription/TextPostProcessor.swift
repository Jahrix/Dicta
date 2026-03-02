import Foundation

@MainActor
struct TextPostProcessor {
    static func process(_ raw: String, settings: SettingsModel) -> String {
        var output = normalizeWhitespace(raw)
        let config = styleConfig(for: settings)

        if config.enableSpokenPunctuation {
            output = applySpokenPunctuation(to: output)
        }

        if settings.phraseMapEnabled {
            output = applyPhraseMap(to: output, settings: settings)
        }

        if config.enableScratchThat {
            output = applyScratchThat(to: output)
        }

        if config.enableFillerRemoval {
            output = removeFillers(from: output)
        }

        if config.enableRepeatedWordCollapse {
            output = collapseRepeatedWords(in: output)
        }

        if config.enableSmartPunctuation {
            output = applySmartPunctuation(to: output,
                                           minWords: settings.minWordsForAutoPeriod,
                                           autoPeriod: config.autoPeriod)
        }

        output = finalCleanup(output)
        return output
    }

    private static func styleConfig(for settings: SettingsModel) -> StyleConfig {
        switch settings.styleMode {
        case .docs:
            return StyleConfig(enableSpokenPunctuation: settings.spokenPunctuationEnabled,
                               enableScratchThat: true,
                               enableFillerRemoval: settings.fillerRemovalEnabled,
                               enableRepeatedWordCollapse: settings.repeatedWordCollapseEnabled,
                               enableSmartPunctuation: settings.smartPunctuationEnabled,
                               autoPeriod: true)
        case .chat:
            return StyleConfig(enableSpokenPunctuation: settings.spokenPunctuationEnabled,
                               enableScratchThat: true,
                               enableFillerRemoval: settings.fillerRemovalEnabled,
                               enableRepeatedWordCollapse: settings.repeatedWordCollapseEnabled,
                               enableSmartPunctuation: settings.smartPunctuationEnabled,
                               autoPeriod: false)
        case .code:
            return StyleConfig(enableSpokenPunctuation: false,
                               enableScratchThat: false,
                               enableFillerRemoval: false,
                               enableRepeatedWordCollapse: false,
                               enableSmartPunctuation: false,
                               autoPeriod: false)
        }
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

    private static func applySmartPunctuation(to text: String, minWords: Int, autoPeriod: Bool) -> String {
        var output = trimTrailingSpacesAndTabs(text)
        let endsWithNewline = output.hasSuffix("\n")
        let terminalCheck = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let endsWithTerminal = terminalCheck.last.map { ".?!".contains($0) } ?? false
        let wordCount = output.split(whereSeparator: { $0.isWhitespace }).count

        if autoPeriod && !endsWithNewline && !endsWithTerminal && wordCount >= max(1, minWords) {
            output.append(".")
        }

        if let first = output.first, first.isLetter {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }

        return output
    }

    private static func applyScratchThat(to text: String) -> String {
        let pattern = "(?i)\\bscratch\\s+that\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = text

        while true {
            let range = NSRange(output.startIndex..., in: output)
            guard let match = regex.firstMatch(in: output, range: range),
                  let matchRange = Range(match.range, in: output) else { break }

            let prefix = output[..<matchRange.lowerBound]
            let removalStart = startIndexForScratchRemoval(prefix: prefix, in: output)
            output.removeSubrange(removalStart..<matchRange.upperBound)
            output = normalizeWhitespacePreservingNewlines(output)
        }

        return output
    }

    private static func startIndexForScratchRemoval(prefix: Substring, in text: String) -> String.Index {
        let boundaryChars = CharacterSet(charactersIn: ".?!;:,")
        if let boundaryIndex = prefix.lastIndex(where: { char in
            char.unicodeScalars.contains { boundaryChars.contains($0) } || char == "\n"
        }) {
            var start = text.index(after: boundaryIndex)
            while start < text.endIndex, text[start].isWhitespace {
                start = text.index(after: start)
            }
            return start
        }

        let fallbackWords = 8
        return startIndexByRemovingTrailingWords(prefix: prefix, in: text, wordCount: fallbackWords)
    }

    private static func startIndexByRemovingTrailingWords(prefix: Substring, in text: String, wordCount: Int) -> String.Index {
        let wordPattern = "\\b[\\p{L}\\p{N}']+\\b"
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else { return text.startIndex }
        let range = NSRange(text.startIndex..<prefix.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text.startIndex }
        let startIndex = max(0, matches.count - wordCount)
        guard let rangeStart = Range(matches[startIndex].range, in: text)?.lowerBound else { return text.startIndex }
        var removalStart = rangeStart
        while removalStart > text.startIndex, text[text.index(before: removalStart)].isWhitespace {
            removalStart = text.index(before: removalStart)
        }
        return removalStart
    }

    private static func removeFillers(from text: String) -> String {
        let pattern = "(?i)\\b(um|uh|erm)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return normalizeWhitespacePreservingNewlines(stripped)
    }

    private static func collapseRepeatedWords(in text: String) -> String {
        let pattern = "\\b([\\p{L}\\p{N}']+)\\b([ \\t]+)\\1\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var output = text
        while true {
            let range = NSRange(output.startIndex..., in: output)
            let replaced = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1")
            if replaced == output { break }
            output = replaced
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

private struct StyleConfig {
    let enableSpokenPunctuation: Bool
    let enableScratchThat: Bool
    let enableFillerRemoval: Bool
    let enableRepeatedWordCollapse: Bool
    let enableSmartPunctuation: Bool
    let autoPeriod: Bool
}
