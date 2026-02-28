import Foundation
import AppKit
import UniformTypeIdentifiers

final class DiagnosticsManager {
    static let shared = DiagnosticsManager()

    private var recentAudio: [URL] = []
    private let audioQueue = DispatchQueue(label: "com.dicta.diagnostics.audio")
    private let logger = DiagnosticsLogger.shared

    private init() {}

    func addRecentAudio(_ url: URL) {
        audioQueue.sync {
            recentAudio.removeAll { $0 == url }
            recentAudio.insert(url, at: 0)
            if recentAudio.count > 3 {
                recentAudio = Array(recentAudio.prefix(3))
            }
        }
    }

    @MainActor
    func exportDebugBundle() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Dicta-Debug-\(timestamp()).zip"
        let response = panel.runModal()
        guard response == .OK, let destinationURL = panel.url else { return }

        Task.detached {
            await self.createBundle(at: destinationURL)
        }
    }

    private func createBundle(at destinationURL: URL) async {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("DictaDebug-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.log(.diagnostics, "Failed to create temp dir: \(error.localizedDescription)")
            return
        }

        if let logURL = await logger.currentLogURL() {
            let logDest = tempDir.appendingPathComponent("dicta.log")
            try? fileManager.copyItem(at: logURL, to: logDest)
        }

        let audioDir = tempDir.appendingPathComponent("audio", isDirectory: true)
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true, attributes: nil)
        let audioCopyList = audioQueue.sync { recentAudio }
        for url in audioCopyList {
            let dest = audioDir.appendingPathComponent(url.lastPathComponent)
            try? fileManager.copyItem(at: url, to: dest)
        }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        if let data = SettingsSnapshot.current().jsonData {
            try? data.write(to: settingsURL)
        }

        let zipTask = Process()
        zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipTask.arguments = ["-r", destinationURL.path, "."]
        zipTask.currentDirectoryURL = tempDir
        do {
            try zipTask.run()
            zipTask.waitUntilExit()
            logger.log(.diagnostics, "Exported debug bundle to \(destinationURL.path)")
        } catch {
            logger.log(.diagnostics, "Zip failed: \(error.localizedDescription)")
        }

        try? fileManager.removeItem(at: tempDir)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

struct SettingsSnapshot: Codable {
    let hotkeyKeyCode: Int
    let hotkeyModifiers: Int
    let insertionMode: String
    let languageIdentifier: String
    let maxRecordingSeconds: Double
    let transcriptionTimeoutSeconds: Double
    let insertionTimeoutSeconds: Double
    let silenceTimeoutSeconds: Double
    let noFramesTimeoutSeconds: Double
    let vadThresholdRMS: Double
    let vadGraceSeconds: Double
    let restoreClipboard: Bool
    let preferOnDevice: Bool
    let showHUD: Bool
    let verboseLogging: Bool

    static func current() -> SettingsSnapshot {
        let defaults = UserDefaults.standard
        return SettingsSnapshot(
            hotkeyKeyCode: defaults.integer(forKey: SettingsModel.Keys.hotkeyKeyCode),
            hotkeyModifiers: defaults.integer(forKey: SettingsModel.Keys.hotkeyModifiers),
            insertionMode: defaults.string(forKey: SettingsModel.Keys.insertionMode) ?? "pasteboard",
            languageIdentifier: defaults.string(forKey: SettingsModel.Keys.languageIdentifier) ?? Locale.current.identifier,
            maxRecordingSeconds: defaults.double(forKey: SettingsModel.Keys.maxRecordingSeconds),
            transcriptionTimeoutSeconds: defaults.double(forKey: SettingsModel.Keys.transcriptionTimeoutSeconds),
            insertionTimeoutSeconds: defaults.double(forKey: SettingsModel.Keys.insertionTimeoutSeconds),
            silenceTimeoutSeconds: defaults.double(forKey: SettingsModel.Keys.silenceTimeoutSeconds),
            noFramesTimeoutSeconds: defaults.double(forKey: SettingsModel.Keys.noFramesTimeoutSeconds),
            vadThresholdRMS: defaults.double(forKey: SettingsModel.Keys.vadThresholdRMS),
            vadGraceSeconds: defaults.double(forKey: SettingsModel.Keys.vadGraceSeconds),
            restoreClipboard: defaults.bool(forKey: SettingsModel.Keys.restoreClipboard),
            preferOnDevice: defaults.bool(forKey: SettingsModel.Keys.preferOnDevice),
            showHUD: defaults.bool(forKey: SettingsModel.Keys.showHUD),
            verboseLogging: defaults.bool(forKey: SettingsModel.Keys.verboseLogging)
        )
    }

    var jsonData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}
