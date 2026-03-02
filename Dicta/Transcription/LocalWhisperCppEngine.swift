import Foundation

final class LocalWhisperCppEngine: TranscriptionEngine {
    private let settings: SettingsModel
    private let logger: DiagnosticsLogger

    init(settings: SettingsModel, logger: DiagnosticsLogger) {
        self.settings = settings
        self.logger = logger
    }

    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult {
        let text = try await transcribeFile(url: url, locale: locale, prompt: settings.customPrompt)
        return TranscriptionResult(text: text, confidence: nil, segmentDurations: nil)
    }

    func transcribeFile(url: URL, locale: Locale, prompt: String) async throws -> String {
        let binaryPath = try resolveBinaryPath()
        let modelPath = try resolveModelPath()
        let timeoutSeconds = settings.transcriptionTimeoutSeconds > 0 ? settings.transcriptionTimeoutSeconds : 20.0

        logger.log(.transcription, "LocalWhisper start (binary: \(binaryPath), model: \(modelPath), locale: \(locale.identifier))")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DictaWhisper-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.currentDirectoryURL = tempDir

        var arguments = ["-m", modelPath, "-f", url.path, "-nt"]
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            arguments.append(contentsOf: ["-p", trimmedPrompt])
        }
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw TranscriptionError.underlying("Failed to launch local whisper: \(error.localizedDescription)")
        }

        do {
            let output = try await withTimeout(seconds: timeoutSeconds, timeoutError: TranscriptionError.timeout) {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let rawStdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let rawStderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let tail = Self.tail(rawStderr, maxChars: 800)
                    throw TranscriptionError.underlying("Local whisper failed (code \(process.terminationStatus)). \(tail)")
                }

                let trimmed = rawStdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = trimmed.split(whereSeparator: \.isNewline).joined(separator: " ")
                if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw TranscriptionError.noSpeechDetected
                }
                return cleaned
            }

            if process.isRunning {
                process.terminate()
            }

            return output
        } catch {
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
    }

    private func resolveBinaryPath() throws -> String {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledPath = resourceURL.appendingPathComponent("whisper/whisper-cpp").path
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
            let flatPath = resourceURL.appendingPathComponent("whisper-cpp").path
            if FileManager.default.fileExists(atPath: flatPath) {
                return flatPath
            }
        }

        let homebrewPath = "/opt/homebrew/bin/whisper-cpp"
        if FileManager.default.fileExists(atPath: homebrewPath) {
            return homebrewPath
        }

        let overridePath = settings.whisperBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overridePath.isEmpty, FileManager.default.fileExists(atPath: overridePath) {
            return overridePath
        }

        let message = "Local whisper binary not found. Expected bundled Resources/whisper/whisper-cpp or /opt/homebrew/bin/whisper-cpp. Set SettingsModel.whisperBinaryPath to override."
        logger.log(.transcription, message)
        throw TranscriptionError.underlying(message)
    }

    private func resolveModelPath() throws -> String {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledModel = resourceURL.appendingPathComponent("models/ggml-small.en.bin").path
            if FileManager.default.fileExists(atPath: bundledModel) {
                return bundledModel
            }
        }

        let overridePath = settings.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overridePath.isEmpty, FileManager.default.fileExists(atPath: overridePath) {
            return overridePath
        }

        let message = "Local whisper model not found. Expected bundled Resources/models/ggml-small.en.bin. Set SettingsModel.whisperModelPath to override."
        logger.log(.transcription, message)
        throw TranscriptionError.underlying(message)
    }

    private func withTimeout<T>(seconds: Double, timeoutError: Error, operation: @escaping () throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw timeoutError
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func tail(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -maxChars)
        return "…\(trimmed[start...])"
    }
}
