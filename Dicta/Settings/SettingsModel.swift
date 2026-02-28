import Foundation
import Combine
import Speech

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotkey: Hotkey { didSet { saveHotkey() } }
    @Published var insertionMode: InsertionMode { didSet { defaults.set(insertionMode.rawValue, forKey: Keys.insertionMode) } }
    @Published var languageIdentifier: String { didSet { defaults.set(languageIdentifier, forKey: Keys.languageIdentifier) } }
    @Published var postProcessorReplacements: [String: String] { didSet { savePostProcessorReplacements() } }
    @Published var postProcessorJSONPath: String { didSet { defaults.set(postProcessorJSONPath, forKey: Keys.postProcessorJSONPath) } }
    @Published var smartPunctuationEnabled: Bool { didSet { defaults.set(smartPunctuationEnabled, forKey: Keys.smartPunctuationEnabled) } }
    @Published var minWordsForAutoPeriod: Int { didSet { defaults.set(minWordsForAutoPeriod, forKey: Keys.minWordsForAutoPeriod) } }
    @Published var phraseMapEnabled: Bool { didSet { defaults.set(phraseMapEnabled, forKey: Keys.phraseMapEnabled) } }
    @Published var phraseMap: [String: String] { didSet { savePhraseMap() } }
    @Published var spokenPunctuationEnabled: Bool { didSet { defaults.set(spokenPunctuationEnabled, forKey: Keys.spokenPunctuationEnabled) } }
    @Published var maxRecordingSeconds: Double { didSet { defaults.set(maxRecordingSeconds, forKey: Keys.maxRecordingSeconds) } }
    @Published var transcriptionTimeoutSeconds: Double { didSet { defaults.set(transcriptionTimeoutSeconds, forKey: Keys.transcriptionTimeoutSeconds) } }
    @Published var insertionTimeoutSeconds: Double { didSet { defaults.set(insertionTimeoutSeconds, forKey: Keys.insertionTimeoutSeconds) } }
    @Published var silenceTimeoutSeconds: Double { didSet { defaults.set(silenceTimeoutSeconds, forKey: Keys.silenceTimeoutSeconds) } }
    @Published var noFramesTimeoutSeconds: Double { didSet { defaults.set(noFramesTimeoutSeconds, forKey: Keys.noFramesTimeoutSeconds) } }
    @Published var vadThresholdRMS: Double { didSet { defaults.set(vadThresholdRMS, forKey: Keys.vadThresholdRMS) } }
    @Published var vadGraceSeconds: Double { didSet { defaults.set(vadGraceSeconds, forKey: Keys.vadGraceSeconds) } }
    @Published var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) } }
    @Published var preferOnDevice: Bool { didSet { defaults.set(preferOnDevice, forKey: Keys.preferOnDevice) } }
    @Published var showHUD: Bool { didSet { defaults.set(showHUD, forKey: Keys.showHUD) } }
    @Published var verboseLogging: Bool { didSet { defaults.set(verboseLogging, forKey: Keys.verboseLogging) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Keys.hotkeyKeyCode: Int(Hotkey.default.keyCode),
            Keys.hotkeyModifiers: Int(Hotkey.default.modifiers),
            Keys.insertionMode: InsertionMode.pasteboard.rawValue,
            Keys.languageIdentifier: Self.defaultLanguageIdentifier(),
            Keys.postProcessorReplacements: Data(),
            Keys.postProcessorJSONPath: "",
            Keys.smartPunctuationEnabled: true,
            Keys.minWordsForAutoPeriod: 8,
            Keys.phraseMapEnabled: true,
            Keys.phraseMapData: Self.encodePhraseMap(PhraseMapStore.builtInMap),
            Keys.spokenPunctuationEnabled: true,
            Keys.maxRecordingSeconds: 60.0,
            Keys.transcriptionTimeoutSeconds: 20.0,
            Keys.insertionTimeoutSeconds: 2.0,
            Keys.silenceTimeoutSeconds: 3.0,
            Keys.noFramesTimeoutSeconds: 0.5,
            Keys.vadThresholdRMS: 0.015,
            Keys.vadGraceSeconds: 0.6,
            Keys.restoreClipboard: true,
            Keys.preferOnDevice: true,
            Keys.showHUD: true,
            Keys.verboseLogging: false,
            Keys.hasCompletedOnboarding: false
        ])

        let keyCode = defaults.integer(forKey: Keys.hotkeyKeyCode)
        let modifiers = defaults.integer(forKey: Keys.hotkeyModifiers)
        let storedLanguage = defaults.string(forKey: Keys.languageIdentifier)
        let languageIdentifierValue = (storedLanguage?.isEmpty == false) ? storedLanguage! : Self.defaultLanguageIdentifier()
        let postProcessorReplacementsValue = Self.decodePostProcessorReplacements(from: defaults.data(forKey: Keys.postProcessorReplacements))
        let postProcessorJSONPathValue = defaults.string(forKey: Keys.postProcessorJSONPath) ?? ""
        let smartPunctuationEnabledValue = defaults.bool(forKey: Keys.smartPunctuationEnabled)
        let minWordsForAutoPeriodValue = max(1, defaults.integer(forKey: Keys.minWordsForAutoPeriod))
        let phraseMapEnabledValue = defaults.bool(forKey: Keys.phraseMapEnabled)
        let spokenPunctuationEnabledValue = defaults.bool(forKey: Keys.spokenPunctuationEnabled)
        var phraseMapValue = Self.decodePhraseMap(from: defaults.data(forKey: Keys.phraseMapData))
        var shouldSavePhraseMap = false
        if phraseMapValue.isEmpty {
            var merged = PhraseMapStore.builtInMap
            let legacy = Self.loadLegacyPhraseMap(from: defaults,
                                                  postProcessorReplacements: postProcessorReplacementsValue,
                                                  postProcessorJSONPath: postProcessorJSONPathValue)
            for (key, value) in legacy {
                merged[key] = value
            }
            phraseMapValue = merged
            shouldSavePhraseMap = true
        }

        hotkey = Hotkey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: Keys.insertionMode) ?? InsertionMode.pasteboard.rawValue) ?? .pasteboard
        languageIdentifier = languageIdentifierValue
        postProcessorReplacements = postProcessorReplacementsValue
        postProcessorJSONPath = postProcessorJSONPathValue
        smartPunctuationEnabled = smartPunctuationEnabledValue
        minWordsForAutoPeriod = minWordsForAutoPeriodValue
        phraseMapEnabled = phraseMapEnabledValue
        phraseMap = phraseMapValue
        spokenPunctuationEnabled = spokenPunctuationEnabledValue
        maxRecordingSeconds = defaults.double(forKey: Keys.maxRecordingSeconds)
        transcriptionTimeoutSeconds = defaults.double(forKey: Keys.transcriptionTimeoutSeconds)
        insertionTimeoutSeconds = defaults.double(forKey: Keys.insertionTimeoutSeconds)
        silenceTimeoutSeconds = defaults.double(forKey: Keys.silenceTimeoutSeconds)
        noFramesTimeoutSeconds = defaults.double(forKey: Keys.noFramesTimeoutSeconds)
        vadThresholdRMS = defaults.double(forKey: Keys.vadThresholdRMS)
        vadGraceSeconds = defaults.double(forKey: Keys.vadGraceSeconds)
        restoreClipboard = defaults.bool(forKey: Keys.restoreClipboard)
        preferOnDevice = defaults.bool(forKey: Keys.preferOnDevice)
        showHUD = defaults.bool(forKey: Keys.showHUD)
        verboseLogging = defaults.bool(forKey: Keys.verboseLogging)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        if shouldSavePhraseMap {
            savePhraseMap()
        }
    }

    private func saveHotkey() {
        defaults.set(Int(hotkey.keyCode), forKey: Keys.hotkeyKeyCode)
        defaults.set(Int(hotkey.modifiers), forKey: Keys.hotkeyModifiers)
    }

    private func savePostProcessorReplacements() {
        guard let data = try? JSONEncoder().encode(postProcessorReplacements) else { return }
        defaults.set(data, forKey: Keys.postProcessorReplacements)
    }

    private func savePhraseMap() {
        defaults.set(Self.encodePhraseMap(phraseMap), forKey: Keys.phraseMapData)
    }

    var selectedLocaleIdentifier: String {
        languageIdentifier
    }

    enum Keys {
        static let hotkeyKeyCode = "dicta.hotkey.keyCode"
        static let hotkeyModifiers = "dicta.hotkey.modifiers"
        static let insertionMode = "dicta.insertion.mode"
        static let languageIdentifier = "dicta.language.identifier"
        static let postProcessorReplacements = "dicta.postProcessor.replacements"
        static let postProcessorJSONPath = "dicta.postProcessor.jsonPath"
        static let smartPunctuationEnabled = "dicta.smartPunctuation.enabled"
        static let minWordsForAutoPeriod = "dicta.smartPunctuation.minWords"
        static let phraseMapEnabled = "dicta.phraseMap.enabled"
        static let phraseMapData = "dicta.phraseMap.data"
        static let spokenPunctuationEnabled = "dicta.spokenPunctuation.enabled"
        static let maxRecordingSeconds = "dicta.maxRecordingSeconds"
        static let transcriptionTimeoutSeconds = "dicta.transcriptionTimeoutSeconds"
        static let insertionTimeoutSeconds = "dicta.insertionTimeoutSeconds"
        static let silenceTimeoutSeconds = "dicta.silenceTimeoutSeconds"
        static let noFramesTimeoutSeconds = "dicta.noFramesTimeoutSeconds"
        static let vadThresholdRMS = "dicta.vadThresholdRMS"
        static let vadGraceSeconds = "dicta.vadGraceSeconds"
        static let restoreClipboard = "dicta.restoreClipboard"
        static let preferOnDevice = "dicta.preferOnDevice"
        static let showHUD = "dicta.showHUD"
        static let verboseLogging = "dicta.verboseLogging"
        static let hasCompletedOnboarding = "dicta.hasCompletedOnboarding"
    }

    private static func defaultLanguageIdentifier() -> String {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { normalizeLocaleIdentifier($0.identifier) })
        if supported.contains("en-US") {
            return "en-US"
        }

        return supported.sorted().first ?? "en-US"
    }

    private static func normalizeLocaleIdentifier(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")
        guard parts.count >= 2 else { return normalized }
        let language = parts[0].lowercased()
        let region = parts[1].uppercased()
        return "\(language)-\(region)"
    }

    private static func decodePostProcessorReplacements(from data: Data?) -> [String: String] {
        guard let data, !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func decodePhraseMap(from data: Data?) -> [String: String] {
        guard let data, !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func encodePhraseMap(_ map: [String: String]) -> Data {
        (try? JSONEncoder().encode(map)) ?? Data()
    }

    private static func loadLegacyPhraseMap(from defaults: UserDefaults,
                                            postProcessorReplacements: [String: String],
                                            postProcessorJSONPath: String) -> [String: String] {
        var merged = postProcessorReplacements
        let trimmedPath = postProcessorJSONPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            let url = URL(fileURLWithPath: trimmedPath)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in json {
                    merged[key] = value
                }
            }
        }
        return merged
    }
}

enum InsertionMode: String, CaseIterable, Identifiable {
    case pasteboard
    case accessibility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pasteboard: return "Pasteboard (Cmd+V)"
        case .accessibility: return "Accessibility Typing"
        }
    }
}
