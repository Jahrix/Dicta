import Foundation
import Combine
import Speech
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class SettingsModel: ObservableObject {
    @Published var pushToTalkKeybind: Keybind { didSet { saveKeybind(pushToTalkKeybind, key: Keys.pushToTalkKeybindData) } }
    @Published var longDictationKeybind: Keybind { didSet { saveKeybind(longDictationKeybind, key: Keys.longDictationKeybindData) } }
    @Published var insertionMode: InsertionMode { didSet { defaults.set(insertionMode.rawValue, forKey: Keys.insertionMode) } }
    @Published var languageIdentifier: String { didSet { defaults.set(languageIdentifier, forKey: Keys.languageIdentifier) } }
    @Published var transcriptionBackend: String { didSet { defaults.set(transcriptionBackend, forKey: Keys.transcriptionBackend) } }
    @Published var transcriptionPreset: String {
        didSet {
            defaults.set(transcriptionPreset, forKey: Keys.transcriptionPreset)
            let oldPreset = TranscriptionPreset(rawValue: oldValue) ?? .accuracy
            let newPreset = TranscriptionPreset(rawValue: transcriptionPreset) ?? .accuracy
            guard oldPreset != newPreset else { return }
            let oldDefaults = Self.presetDefaults(for: oldPreset)
            let newDefaults = Self.presetDefaults(for: newPreset)
            if beamSize == oldDefaults.beamSize { beamSize = newDefaults.beamSize }
            if abs(temperature - oldDefaults.temperature) < 0.0001 { temperature = newDefaults.temperature }
            if bestOf == oldDefaults.bestOf { bestOf = newDefaults.bestOf }
        }
    }
    @Published var whisperBinaryPath: String { didSet { defaults.set(whisperBinaryPath, forKey: Keys.whisperBinaryPath) } }
    @Published var whisperModelPath: String { didSet { defaults.set(whisperModelPath, forKey: Keys.whisperModelPath) } }
    @Published var selectedModelTier: SpeechModelTier { didSet { defaults.set(selectedModelTier.rawValue, forKey: Keys.selectedModelTier) } }
    @Published var modelDirectoryPath: String { didSet { defaults.set(modelDirectoryPath, forKey: Keys.modelDirectoryPath) } }
    @Published var showLocalPrivacyCopy: Bool { didSet { defaults.set(showLocalPrivacyCopy, forKey: Keys.showLocalPrivacyCopy) } }
    @Published var beamSize: Int { didSet { defaults.set(beamSize, forKey: Keys.beamSize) } }
    @Published var temperature: Double { didSet { defaults.set(temperature, forKey: Keys.temperature) } }
    @Published var bestOf: Int { didSet { defaults.set(bestOf, forKey: Keys.bestOf) } }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.languageCode) } }
    @Published var customPrompt: String { didSet { defaults.set(customPrompt, forKey: Keys.customPrompt) } }
    @Published var postProcessorReplacements: [String: String] { didSet { savePostProcessorReplacements() } }
    @Published var postProcessorJSONPath: String { didSet { defaults.set(postProcessorJSONPath, forKey: Keys.postProcessorJSONPath) } }
    @Published var smartPunctuationEnabled: Bool { didSet { defaults.set(smartPunctuationEnabled, forKey: Keys.smartPunctuationEnabled) } }
    @Published var minWordsForAutoPeriod: Int { didSet { defaults.set(minWordsForAutoPeriod, forKey: Keys.minWordsForAutoPeriod) } }
    @Published var phraseMapEnabled: Bool { didSet { defaults.set(phraseMapEnabled, forKey: Keys.phraseMapEnabled) } }
    @Published var phraseMap: [String: String] { didSet { savePhraseMap() } }
    @Published var spokenPunctuationEnabled: Bool { didSet { defaults.set(spokenPunctuationEnabled, forKey: Keys.spokenPunctuationEnabled) } }
    @Published var fillerRemovalEnabled: Bool { didSet { defaults.set(fillerRemovalEnabled, forKey: Keys.fillerRemovalEnabled) } }
    @Published var repeatedWordCollapseEnabled: Bool { didSet { defaults.set(repeatedWordCollapseEnabled, forKey: Keys.repeatedWordCollapseEnabled) } }
    @Published var styleMode: StyleMode { didSet { defaults.set(styleMode.rawValue, forKey: Keys.styleMode) } }
    @Published var partialWindowSeconds: Double { didSet { defaults.set(partialWindowSeconds, forKey: Keys.partialWindowSeconds) } }
    @Published var partialIntervalSeconds: Double { didSet { defaults.set(partialIntervalSeconds, forKey: Keys.partialIntervalSeconds) } }
    @Published var streamingEnabled: Bool { didSet { defaults.set(streamingEnabled, forKey: Keys.streamingEnabled) } }
    @Published var maxRecordingSeconds: Double { didSet { defaults.set(maxRecordingSeconds, forKey: Keys.maxRecordingSeconds) } }
    @Published var transcriptionTimeoutSeconds: Double { didSet { defaults.set(transcriptionTimeoutSeconds, forKey: Keys.transcriptionTimeoutSeconds) } }
    @Published var partialTranscriptionTimeoutSeconds: Double { didSet { defaults.set(partialTranscriptionTimeoutSeconds, forKey: Keys.partialTranscriptionTimeoutSeconds) } }
    @Published var insertionTimeoutSeconds: Double { didSet { defaults.set(insertionTimeoutSeconds, forKey: Keys.insertionTimeoutSeconds) } }
    @Published var silenceTimeoutSeconds: Double { didSet { defaults.set(silenceTimeoutSeconds, forKey: Keys.silenceTimeoutSeconds) } }
    @Published var noFramesTimeoutSeconds: Double { didSet { defaults.set(noFramesTimeoutSeconds, forKey: Keys.noFramesTimeoutSeconds) } }
    @Published var vadThresholdRMS: Double { didSet { defaults.set(vadThresholdRMS, forKey: Keys.vadThresholdRMS) } }
    @Published var vadGraceSeconds: Double { didSet { defaults.set(vadGraceSeconds, forKey: Keys.vadGraceSeconds) } }
    @Published var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) } }
    @Published var preferOnDevice: Bool { didSet { defaults.set(preferOnDevice, forKey: Keys.preferOnDevice) } }
    @Published var showHUD: Bool { didSet { defaults.set(showHUD, forKey: Keys.showHUD) } }
    @Published var themeMode: ThemeMode { didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) } }
    @Published var selectedThemeID: String { didSet { defaults.set(selectedThemeID, forKey: Keys.selectedThemeID) } }
    @Published var customThemeEnabled: Bool { didSet { defaults.set(customThemeEnabled, forKey: Keys.customThemeEnabled) } }
    @Published var customThemeHex: String { didSet { defaults.set(customThemeHex, forKey: Keys.customThemeHex) } }
    @Published var hudPositionX: Double { didSet { defaults.set(hudPositionX, forKey: Keys.hudPositionX) } }
    @Published var hudPositionY: Double { didSet { defaults.set(hudPositionY, forKey: Keys.hudPositionY) } }
    @Published var hasCustomHUDPosition: Bool { didSet { defaults.set(hasCustomHUDPosition, forKey: Keys.hasCustomHUDPosition) } }
    @Published var hasShownInputMonitoringHint: Bool { didSet { defaults.set(hasShownInputMonitoringHint, forKey: Keys.hasShownInputMonitoringHint) } }
    @Published var verboseLogging: Bool { didSet { defaults.set(verboseLogging, forKey: Keys.verboseLogging) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Keys.pushToTalkKeybindData: Self.encodeKeybind(Keybind.defaultPushToTalk),
            Keys.longDictationKeybindData: Self.encodeKeybind(Keybind.defaultLongDictation),
            Keys.insertionMode: InsertionMode.pasteboard.rawValue,
            Keys.languageIdentifier: Self.defaultLanguageIdentifier(),
            Keys.transcriptionBackend: TranscriptionBackend.localWhisperCpp.rawValue,
            Keys.transcriptionPreset: TranscriptionPreset.accuracy.rawValue,
            Keys.whisperBinaryPath: "",
            Keys.whisperModelPath: "",
            Keys.selectedModelTier: SpeechModelTier.small.rawValue,
            Keys.modelDirectoryPath: "",
            Keys.showLocalPrivacyCopy: true,
            Keys.beamSize: 5,
            Keys.temperature: 0.0,
            Keys.bestOf: 3,
            Keys.languageCode: "en",
            Keys.customPrompt: "",
            Keys.postProcessorReplacements: Data(),
            Keys.postProcessorJSONPath: "",
            Keys.smartPunctuationEnabled: true,
            Keys.minWordsForAutoPeriod: 8,
            Keys.phraseMapEnabled: true,
            Keys.phraseMapData: Self.encodePhraseMap(PhraseMapStore.builtInMap),
            Keys.spokenPunctuationEnabled: true,
            Keys.fillerRemovalEnabled: true,
            Keys.repeatedWordCollapseEnabled: true,
            Keys.styleMode: StyleMode.docs.rawValue,
            Keys.partialWindowSeconds: 4.0,
            Keys.partialIntervalSeconds: 1.8,
            Keys.streamingEnabled: false,
            Keys.maxRecordingSeconds: 60.0,
            Keys.transcriptionTimeoutSeconds: 30.0,
            Keys.partialTranscriptionTimeoutSeconds: 12.0,
            Keys.insertionTimeoutSeconds: 2.0,
            Keys.silenceTimeoutSeconds: 3.0,
            Keys.noFramesTimeoutSeconds: 0.5,
            Keys.vadThresholdRMS: 0.015,
            Keys.vadGraceSeconds: 0.6,
            Keys.restoreClipboard: false,
            Keys.preferOnDevice: true,
            Keys.showHUD: true,
            Keys.themeMode: ThemeMode.system.rawValue,
            Keys.selectedThemeID: RoyalThemes.defaultTheme.id,
            Keys.customThemeEnabled: false,
            Keys.customThemeHex: "",
            Keys.hudPositionX: 0.0,
            Keys.hudPositionY: 0.0,
            Keys.hasCustomHUDPosition: false,
            Keys.hasShownInputMonitoringHint: false,
            Keys.verboseLogging: false,
            Keys.hasCompletedOnboarding: false,
            Keys.hotkeyKeyCode: Int(UInt32(kVK_Space)),
            Keys.hotkeyModifiers: Int(optionKey)
        ])

        let transcriptionPresetValue = defaults.string(forKey: Keys.transcriptionPreset) ?? TranscriptionPreset.accuracy.rawValue
        let presetDefaults = Self.presetDefaults(for: TranscriptionPreset(rawValue: transcriptionPresetValue) ?? .accuracy)

        let pushToTalkValue = Self.loadKeybind(from: defaults.data(forKey: Keys.pushToTalkKeybindData))
        let longDictationValue = Self.loadKeybind(from: defaults.data(forKey: Keys.longDictationKeybindData))
        let legacyHotkey = Self.loadLegacyHotkey(from: defaults)

        let hasPushToTalkStored = defaults.object(forKey: Keys.pushToTalkKeybindData) != nil
        let hasLongStored = defaults.object(forKey: Keys.longDictationKeybindData) != nil

        let resolvedPushToTalk = hasPushToTalkStored ? (pushToTalkValue ?? .defaultPushToTalk) : .defaultPushToTalk
        let resolvedLong = hasLongStored ? (longDictationValue ?? .defaultLongDictation) : (legacyHotkey ?? .defaultLongDictation)

        let languageIdentifierValue = Self.normalizeLocaleIdentifier(defaults.string(forKey: Keys.languageIdentifier) ?? Self.defaultLanguageIdentifier())
        let transcriptionBackendValue = defaults.string(forKey: Keys.transcriptionBackend) ?? TranscriptionBackend.localWhisperCpp.rawValue
        let whisperBinaryPathValue = defaults.string(forKey: Keys.whisperBinaryPath) ?? ""
        let whisperModelPathValue = defaults.string(forKey: Keys.whisperModelPath) ?? ""
        let selectedModelTierValue = SpeechModelTier(rawValue: defaults.string(forKey: Keys.selectedModelTier) ?? SpeechModelTier.small.rawValue) ?? .small
        let modelDirectoryPathValue = defaults.string(forKey: Keys.modelDirectoryPath) ?? ""
        let showLocalPrivacyCopyValue = defaults.bool(forKey: Keys.showLocalPrivacyCopy)
        let beamSizeValue = defaults.object(forKey: Keys.beamSize) != nil ? max(1, defaults.integer(forKey: Keys.beamSize)) : presetDefaults.beamSize
        let temperatureValue = defaults.object(forKey: Keys.temperature) != nil ? min(max(defaults.double(forKey: Keys.temperature), 0.0), 1.0) : presetDefaults.temperature
        let bestOfValue = defaults.object(forKey: Keys.bestOf) != nil ? max(1, defaults.integer(forKey: Keys.bestOf)) : presetDefaults.bestOf
        let languageCodeValue = defaults.string(forKey: Keys.languageCode) ?? "en"
        let customPromptValue = defaults.string(forKey: Keys.customPrompt) ?? ""
        let postProcessorReplacementsValue = Self.decodePostProcessorReplacements(from: defaults.data(forKey: Keys.postProcessorReplacements))
        let postProcessorJSONPathValue = defaults.string(forKey: Keys.postProcessorJSONPath) ?? ""
        let smartPunctuationEnabledValue = defaults.bool(forKey: Keys.smartPunctuationEnabled)
        let minWordsForAutoPeriodValue = max(1, defaults.integer(forKey: Keys.minWordsForAutoPeriod))
        let phraseMapEnabledValue = defaults.bool(forKey: Keys.phraseMapEnabled)
        let spokenPunctuationEnabledValue = defaults.bool(forKey: Keys.spokenPunctuationEnabled)
        let fillerRemovalEnabledValue = defaults.bool(forKey: Keys.fillerRemovalEnabled)
        let repeatedWordCollapseEnabledValue = defaults.bool(forKey: Keys.repeatedWordCollapseEnabled)
        let styleModeValue = StyleMode(rawValue: defaults.string(forKey: Keys.styleMode) ?? StyleMode.docs.rawValue) ?? .docs
        let partialWindowSecondsValue = defaults.double(forKey: Keys.partialWindowSeconds)
        let partialIntervalSecondsValue = defaults.double(forKey: Keys.partialIntervalSeconds)
        let streamingEnabledValue = defaults.bool(forKey: Keys.streamingEnabled)
        let themeModeValue = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? ThemeMode.system.rawValue) ?? .system
        let selectedThemeIDValue = defaults.string(forKey: Keys.selectedThemeID) ?? RoyalThemes.defaultTheme.id
        let customThemeEnabledValue = defaults.bool(forKey: Keys.customThemeEnabled)
        let customThemeHexValue = defaults.string(forKey: Keys.customThemeHex) ?? ""
        let partialTranscriptionTimeoutValue = defaults.double(forKey: Keys.partialTranscriptionTimeoutSeconds)
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

        pushToTalkKeybind = resolvedPushToTalk
        longDictationKeybind = resolvedLong
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: Keys.insertionMode) ?? InsertionMode.pasteboard.rawValue) ?? .pasteboard
        languageIdentifier = languageIdentifierValue
        transcriptionBackend = transcriptionBackendValue
        transcriptionPreset = transcriptionPresetValue
        whisperBinaryPath = whisperBinaryPathValue
        whisperModelPath = whisperModelPathValue
        selectedModelTier = selectedModelTierValue
        modelDirectoryPath = modelDirectoryPathValue
        showLocalPrivacyCopy = showLocalPrivacyCopyValue
        beamSize = beamSizeValue
        temperature = temperatureValue
        bestOf = bestOfValue
        languageCode = languageCodeValue.isEmpty ? "en" : languageCodeValue
        customPrompt = customPromptValue
        postProcessorReplacements = postProcessorReplacementsValue
        postProcessorJSONPath = postProcessorJSONPathValue
        smartPunctuationEnabled = smartPunctuationEnabledValue
        minWordsForAutoPeriod = minWordsForAutoPeriodValue
        phraseMapEnabled = phraseMapEnabledValue
        phraseMap = phraseMapValue
        spokenPunctuationEnabled = spokenPunctuationEnabledValue
        fillerRemovalEnabled = fillerRemovalEnabledValue
        repeatedWordCollapseEnabled = repeatedWordCollapseEnabledValue
        styleMode = styleModeValue
        partialWindowSeconds = partialWindowSecondsValue > 0 ? partialWindowSecondsValue : 4.0
        partialIntervalSeconds = partialIntervalSecondsValue > 0 ? partialIntervalSecondsValue : 1.8
        streamingEnabled = streamingEnabledValue
        maxRecordingSeconds = defaults.double(forKey: Keys.maxRecordingSeconds)
        transcriptionTimeoutSeconds = defaults.double(forKey: Keys.transcriptionTimeoutSeconds)
        partialTranscriptionTimeoutSeconds = partialTranscriptionTimeoutValue > 0 ? partialTranscriptionTimeoutValue : 12.0
        insertionTimeoutSeconds = defaults.double(forKey: Keys.insertionTimeoutSeconds)
        silenceTimeoutSeconds = defaults.double(forKey: Keys.silenceTimeoutSeconds)
        noFramesTimeoutSeconds = defaults.double(forKey: Keys.noFramesTimeoutSeconds)
        vadThresholdRMS = defaults.double(forKey: Keys.vadThresholdRMS)
        vadGraceSeconds = defaults.double(forKey: Keys.vadGraceSeconds)
        restoreClipboard = defaults.bool(forKey: Keys.restoreClipboard)
        preferOnDevice = defaults.bool(forKey: Keys.preferOnDevice)
        showHUD = defaults.bool(forKey: Keys.showHUD)
        themeMode = themeModeValue
        selectedThemeID = selectedThemeIDValue
        customThemeEnabled = customThemeEnabledValue
        customThemeHex = customThemeHexValue
        hudPositionX = defaults.double(forKey: Keys.hudPositionX)
        hudPositionY = defaults.double(forKey: Keys.hudPositionY)
        hasCustomHUDPosition = defaults.bool(forKey: Keys.hasCustomHUDPosition)
        hasShownInputMonitoringHint = defaults.bool(forKey: Keys.hasShownInputMonitoringHint)
        verboseLogging = defaults.bool(forKey: Keys.verboseLogging)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        if shouldSavePhraseMap {
            savePhraseMap()
        }
        if !hasPushToTalkStored {
            saveKeybind(pushToTalkKeybind, key: Keys.pushToTalkKeybindData)
        }
        if !hasLongStored {
            saveKeybind(longDictationKeybind, key: Keys.longDictationKeybindData)
        }
    }

    var selectedLocaleIdentifier: String {
        languageIdentifier
    }

    var effectiveTheme: Theme {
        ThemeManager.effectiveTheme(selectedID: selectedThemeID,
                                    customHexEnabled: customThemeEnabled,
                                    customHex: customThemeHex)
    }

    var customThemeHexIsValid: Bool {
        ThemeManager.normalizedHex(customThemeHex) != nil
    }

    var themeTintColor: Color {
        ThemeManager.swiftUIColor(from: effectiveTheme.primaryHex)
    }

    func effectivePrompt() -> String {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        guard phraseMapEnabled else { return "" }
        var normalized: [String] = []
        normalized.reserveCapacity(phraseMap.count)
        for value in phraseMap.values {
            let item = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                normalized.append(item)
            }
        }
        guard !normalized.isEmpty else { return "" }
        var seen = Set<String>()
        var unique: [String] = []
        for item in normalized {
            let key = item.lowercased()
            if seen.insert(key).inserted {
                unique.append(item)
            }
        }
        unique.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let prefix = "Proper nouns: "
        var resultItems: [String] = []
        var length = prefix.count
        for item in unique {
            let extra = resultItems.isEmpty ? item.count : item.count + 2
            if length + extra > 400 { break }
            resultItems.append(item)
            length += extra
            if resultItems.count >= 50 { break }
        }
        guard !resultItems.isEmpty else { return "" }
        return prefix + resultItems.joined(separator: ", ")
    }

    enum Keys {
        static let hotkeyKeyCode = "dicta.hotkey.keyCode"
        static let hotkeyModifiers = "dicta.hotkey.modifiers"
        static let pushToTalkKeybindData = "dicta.keybind.pushToTalk"
        static let longDictationKeybindData = "dicta.keybind.longDictation"
        static let insertionMode = "dicta.insertion.mode"
        static let languageIdentifier = "dicta.language.identifier"
        static let transcriptionBackend = "dicta.transcription.backend"
        static let transcriptionPreset = "dicta.transcription.preset"
        static let whisperBinaryPath = "dicta.whisper.binaryPath"
        static let whisperModelPath = "dicta.whisper.modelPath"
        static let selectedModelTier = "dicta.whisper.modelTier"
        static let modelDirectoryPath = "dicta.whisper.modelDirectoryPath"
        static let showLocalPrivacyCopy = "dicta.whisper.showLocalPrivacyCopy"
        static let beamSize = "dicta.whisper.beamSize"
        static let temperature = "dicta.whisper.temperature"
        static let bestOf = "dicta.whisper.bestOf"
        static let languageCode = "dicta.whisper.languageCode"
        static let customPrompt = "dicta.transcription.prompt"
        static let postProcessorReplacements = "dicta.postProcessor.replacements"
        static let postProcessorJSONPath = "dicta.postProcessor.jsonPath"
        static let smartPunctuationEnabled = "dicta.smartPunctuation.enabled"
        static let minWordsForAutoPeriod = "dicta.smartPunctuation.minWords"
        static let phraseMapEnabled = "dicta.phraseMap.enabled"
        static let phraseMapData = "dicta.phraseMap.data"
        static let spokenPunctuationEnabled = "dicta.spokenPunctuation.enabled"
        static let fillerRemovalEnabled = "dicta.postProcessor.fillerRemoval"
        static let repeatedWordCollapseEnabled = "dicta.postProcessor.repeatCollapse"
        static let styleMode = "dicta.postProcessor.styleMode"
        static let partialWindowSeconds = "dicta.partial.windowSeconds"
        static let partialIntervalSeconds = "dicta.partial.intervalSeconds"
        static let streamingEnabled = "dicta.streaming.enabled"
        static let maxRecordingSeconds = "dicta.maxRecordingSeconds"
        static let transcriptionTimeoutSeconds = "dicta.transcriptionTimeoutSeconds"
        static let partialTranscriptionTimeoutSeconds = "dicta.partialTranscriptionTimeoutSeconds"
        static let insertionTimeoutSeconds = "dicta.insertionTimeoutSeconds"
        static let silenceTimeoutSeconds = "dicta.silenceTimeoutSeconds"
        static let noFramesTimeoutSeconds = "dicta.noFramesTimeoutSeconds"
        static let vadThresholdRMS = "dicta.vadThresholdRMS"
        static let vadGraceSeconds = "dicta.vadGraceSeconds"
        static let restoreClipboard = "dicta.restoreClipboard"
        static let preferOnDevice = "dicta.preferOnDevice"
        static let showHUD = "dicta.showHUD"
        static let themeMode = "dicta.themeMode"
        static let selectedThemeID = "dicta.theme.selectedID"
        static let customThemeEnabled = "dicta.theme.customEnabled"
        static let customThemeHex = "dicta.theme.customHex"
        static let hudPositionX = "dicta.hud.positionX"
        static let hudPositionY = "dicta.hud.positionY"
        static let hasCustomHUDPosition = "dicta.hud.hasCustomPosition"
        static let hasShownInputMonitoringHint = "dicta.inputMonitoring.hasShownHint"
        static let verboseLogging = "dicta.verboseLogging"
        static let hasCompletedOnboarding = "dicta.hasCompletedOnboarding"
    }

    enum TranscriptionBackend: String {
        case appleSpeech = "apple_speech"
        case localWhisperCpp = "local_whisper_cpp"
    }

    enum TranscriptionPreset: String, CaseIterable {
        case accuracy
        case latency
    }

    enum ThemeMode: String, CaseIterable {
        case system
        case light
        case dark
    }

    enum StyleMode: String, CaseIterable, Identifiable {
        case docs
        case chat
        case code

        var id: String { rawValue }
    }

    static func presetDefaults(for preset: TranscriptionPreset) -> (beamSize: Int, temperature: Double, bestOf: Int) {
        switch preset {
        case .accuracy:
            return (beamSize: 5, temperature: 0.0, bestOf: 3)
        case .latency:
            return (beamSize: 3, temperature: 0.1, bestOf: 1)
        }
    }

    private static func defaultLanguageIdentifier() -> String {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { normalizeLocaleIdentifier($0.identifier) })
        if supported.contains("en-US") { return "en-US" }
        return supported.sorted().first ?? "en-US"
    }

    private func savePostProcessorReplacements() {
        guard let data = try? JSONEncoder().encode(postProcessorReplacements) else { return }
        defaults.set(data, forKey: Keys.postProcessorReplacements)
    }

    private func savePhraseMap() {
        defaults.set(Self.encodePhraseMap(phraseMap), forKey: Keys.phraseMapData)
    }

    private func saveKeybind(_ keybind: Keybind, key: String) {
        defaults.set(Self.encodeKeybind(keybind), forKey: key)
    }

    private static func loadKeybind(from data: Data?) -> Keybind? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Keybind.self, from: data)
    }

    private static func encodeKeybind(_ keybind: Keybind) -> Data {
        (try? JSONEncoder().encode(keybind)) ?? Data()
    }

    private static func loadLegacyHotkey(from defaults: UserDefaults) -> Keybind? {
        guard defaults.object(forKey: Keys.hotkeyKeyCode) != nil else { return nil }
        let keyCode = UInt16(defaults.integer(forKey: Keys.hotkeyKeyCode))
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Keys.hotkeyModifiers))).hotkeyRelevant
        return Keybind(keyCode: keyCode, modifiers: modifiers, kind: .combo, side: nil)
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

    private static func normalizeLocaleIdentifier(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")
        guard parts.count >= 2 else { return normalized }
        let language = parts[0].lowercased()
        let region = parts[1].uppercased()
        return "\(language)-\(region)"
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
