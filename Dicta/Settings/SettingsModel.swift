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
        hotkey = Hotkey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: Keys.insertionMode) ?? InsertionMode.pasteboard.rawValue) ?? .pasteboard
        let storedLanguage = defaults.string(forKey: Keys.languageIdentifier)
        languageIdentifier = (storedLanguage?.isEmpty == false) ? storedLanguage! : Self.defaultLanguageIdentifier()
        postProcessorReplacements = Self.decodePostProcessorReplacements(from: defaults.data(forKey: Keys.postProcessorReplacements))
        postProcessorJSONPath = defaults.string(forKey: Keys.postProcessorJSONPath) ?? ""
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
    }

    private func saveHotkey() {
        defaults.set(Int(hotkey.keyCode), forKey: Keys.hotkeyKeyCode)
        defaults.set(Int(hotkey.modifiers), forKey: Keys.hotkeyModifiers)
    }

    private func savePostProcessorReplacements() {
        guard let data = try? JSONEncoder().encode(postProcessorReplacements) else { return }
        defaults.set(data, forKey: Keys.postProcessorReplacements)
    }

    enum Keys {
        static let hotkeyKeyCode = "dicta.hotkey.keyCode"
        static let hotkeyModifiers = "dicta.hotkey.modifiers"
        static let insertionMode = "dicta.insertion.mode"
        static let languageIdentifier = "dicta.language.identifier"
        static let postProcessorReplacements = "dicta.postProcessor.replacements"
        static let postProcessorJSONPath = "dicta.postProcessor.jsonPath"
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
