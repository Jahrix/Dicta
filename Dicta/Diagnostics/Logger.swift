import Foundation
import os

enum LogCategory: String {
    case hotkey = "Hotkey"
    case audio = "Audio"
    case transcription = "Transcription"
    case insertion = "Insertion"
    case ui = "UI"
    case permissions = "Permissions"
    case state = "State"
    case diagnostics = "Diagnostics"
}

final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    private let subsystem = "com.dicta.Dicta"
    private let logStore = LogStore()
    private let queue = DispatchQueue(label: "com.dicta.logger", qos: .utility)

    var verboseEnabled = false

    private init() {}

    func log(_ category: LogCategory, _ message: String, verbose: Bool = false) {
        if verbose && !verboseEnabled { return }
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.info("\(message, privacy: .public)")
        let line = "[\(timestamp())] [\(category.rawValue)] \(message)"
        queue.async {
            Task { await self.logStore.append(line) }
        }
    }

    func currentLogURL() async -> URL? {
        await logStore.logFileURL
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

actor LogStore {
    private let maxBytes: UInt64 = 1_000_000
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let logFile: URL
    private let rotatedFile: URL

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        logDirectory = base!.appendingPathComponent("Dicta/Logs", isDirectory: true)
        logFile = logDirectory.appendingPathComponent("dicta.log")
        rotatedFile = logDirectory.appendingPathComponent("dicta.log.1")
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }
    }

    var logFileURL: URL { logFile }

    func append(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        rotateIfNeeded(additionalBytes: UInt64(data.count))
        guard let handle = try? FileHandle(forWritingTo: logFile) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rotateIfNeeded(additionalBytes: UInt64) {
        let size = (try? fileManager.attributesOfItem(atPath: logFile.path)[.size] as? UInt64) ?? 0
        if size + additionalBytes < maxBytes { return }
        try? fileManager.removeItem(at: rotatedFile)
        try? fileManager.moveItem(at: logFile, to: rotatedFile)
        fileManager.createFile(atPath: logFile.path, contents: nil)
    }
}
