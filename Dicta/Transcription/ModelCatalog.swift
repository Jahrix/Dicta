import Foundation

@MainActor
struct ModelCatalog {
    static let missingModelMessage = "Model file not found. Install model or choose another tier."

    static func resolveModelURL(tier: SpeechModelTier, settings: SettingsModel) -> URL? {
        let filename = tier.defaultModelFilename
        let fileManager = FileManager.default

        let overrideDirectory = settings.modelDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overrideDirectory.isEmpty {
            let url = URL(fileURLWithPath: overrideDirectory).appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("models").appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let legacyPath = settings.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacyPath.isEmpty {
            let url = URL(fileURLWithPath: legacyPath)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    static func resolveModelDirectoryURL(settings: SettingsModel) -> URL? {
        let overrideDirectory = settings.modelDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overrideDirectory.isEmpty {
            return URL(fileURLWithPath: overrideDirectory)
        }

        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("models")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let legacyPath = settings.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacyPath.isEmpty {
            return URL(fileURLWithPath: legacyPath).deletingLastPathComponent()
        }

        return nil
    }
}
