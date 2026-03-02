import Foundation

@MainActor
final class LocalWhisperCppEngine: TranscriptionEngine {
    private let settings: SettingsModel
    private let logger: DiagnosticsLogger
    private static var cachedSupportedFlags: [String: SupportedFlags] = [:]
    private let cacheLock = NSLock()

    init(settings: SettingsModel, logger: DiagnosticsLogger) {
        self.settings = settings
        self.logger = logger
    }

    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult {
        let text = try await transcribeFile(url: url, locale: locale, prompt: settings.effectivePrompt())
        return TranscriptionResult(text: text, confidence: nil, segmentDurations: nil)
    }

    func transcribeFile(url: URL, locale: Locale, prompt: String) async throws -> String {
        let binaryPath = try resolveBinaryPath()
        let modelPath = try resolveModelPath()
        let finalTimeoutSeconds = settings.transcriptionTimeoutSeconds > 0 ? settings.transcriptionTimeoutSeconds : 30.0
        let partialTimeoutSetting = settings.partialTranscriptionTimeoutSeconds > 0 ? settings.partialTranscriptionTimeoutSeconds : 12.0
        let partialTimeoutSeconds = min(partialTimeoutSetting, finalTimeoutSeconds)
        let supportedFlags = await loadSupportedFlags(binaryPath: binaryPath, timeoutSeconds: partialTimeoutSeconds)

        let preset = SettingsModel.TranscriptionPreset(rawValue: settings.transcriptionPreset) ?? .accuracy
        let presetDefaults = SettingsModel.presetDefaults(for: preset)
        let beamSize = settings.beamSize > 0 ? settings.beamSize : presetDefaults.beamSize
        let temperature = settings.temperature >= 0.0 && settings.temperature <= 1.0 ? settings.temperature : presetDefaults.temperature
        let bestOf = settings.bestOf > 0 ? settings.bestOf : presetDefaults.bestOf
        let binaryLabel = redactedPath(binaryPath)
        let modelLabel = redactedPath(modelPath)
        logger.log(.transcription, "LocalWhisper preset=\(preset.rawValue) beam=\(beamSize) temp=\(String(format: \"%.2f\", temperature)) bestOf=\(bestOf) model=\(modelLabel) binary=\(binaryLabel) locale=\(locale.identifier)")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DictaWhisper-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.currentDirectoryURL = tempDir

        var arguments = ["-m", modelPath, "-f", url.path, "-nt"]
        let language = settings.languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let flag = supportedFlags.languageFlag, !language.isEmpty {
            arguments.append(contentsOf: [flag, language])
        }
        if let flag = supportedFlags.beamSizeFlag {
            arguments.append(contentsOf: [flag, String(beamSize)])
        }
        if let flag = supportedFlags.temperatureFlag {
            arguments.append(contentsOf: [flag, String(temperature)])
        }
        if let flag = supportedFlags.bestOfFlag {
            arguments.append(contentsOf: [flag, String(bestOf)])
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let flag = supportedFlags.promptFlag, !trimmedPrompt.isEmpty {
            arguments.append(contentsOf: [flag, trimmedPrompt])
        }
        process.arguments = arguments
        logger.log(.transcription, "LocalWhisper args: \(redactedArguments(arguments))")

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
            let output = try await withTimeout(seconds: finalTimeoutSeconds, timeoutError: TranscriptionError.timeout) {
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
        let tier = settings.selectedModelTier
        if let resolvedURL = ModelCatalog.resolveModelURL(tier: tier, settings: settings) {
            let resolvedPath = resolvedURL.path
            logger.log(.transcription, "LocalASR model tier: \(tier.displayName) (path: \(redactedPath(resolvedPath)))")
            return resolvedPath
        }

        logger.log(.transcription, "Model tier \(tier.displayName) unavailable. \(ModelCatalog.missingModelMessage) Falling back to legacy model path.")
        let legacyPath = try resolveLegacyModelPath()
        logger.log(.transcription, "LocalASR model fallback path: \(redactedPath(legacyPath))")
        return legacyPath
    }

    private func resolveLegacyModelPath() throws -> String {
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

    private struct SupportedFlags {
        let beamSizeFlag: String?
        let temperatureFlag: String?
        let bestOfFlag: String?
        let languageFlag: String?
        let promptFlag: String?
    }

    private func loadSupportedFlags(binaryPath: String, timeoutSeconds: Double) async -> SupportedFlags {
        cacheLock.lock()
        if let cached = Self.cachedSupportedFlags[binaryPath] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let helpOutput = await readHelpOutput(binaryPath: binaryPath, timeoutSeconds: timeoutSeconds)
        let lower = helpOutput?.lowercased() ?? ""

        let beamFlag = lower.contains("beam-size") ? "--beam-size" : (lower.contains(" -b ") || lower.contains("\n-b ") ? "-b" : nil)
        let tempFlag = lower.contains("temperature") ? "--temperature" : nil
        let bestOfFlag = lower.contains("best-of") ? "--best-of" : nil
        let languageFlag = lower.contains("--language") ? "--language" : (lower.contains(" -l ") || lower.contains("\n-l ") ? "-l" : nil)
        let promptFlag = lower.contains("--prompt") ? "--prompt" : (lower.contains(" -p ") || lower.contains("\n-p ") ? "-p" : nil)

        let supported = SupportedFlags(beamSizeFlag: beamFlag,
                                       temperatureFlag: tempFlag,
                                       bestOfFlag: bestOfFlag,
                                       languageFlag: languageFlag,
                                       promptFlag: promptFlag)
        cacheLock.lock()
        Self.cachedSupportedFlags[binaryPath] = supported
        cacheLock.unlock()
        return supported
    }

    private func readHelpOutput(binaryPath: String, timeoutSeconds: Double) async -> String? {
        let attempts = [["--help"], ["-h"]]
        for args in attempts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                continue
            }

            let output = try? await withTimeout(seconds: timeoutSeconds, timeoutError: TranscriptionError.timeout) {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                return stdoutText + "\n" + stderrText
            }
            if process.isRunning {
                process.terminate()
            }
            if let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return output
            }
        }
        return nil
    }

    private func redactedArguments(_ args: [String]) -> String {
        var output: [String] = []
        var redactNext: String?
        for arg in args {
            if let redact = redactNext {
                output.append(redact)
                redactNext = nil
                continue
            }
            switch arg {
            case "-m":
                output.append(arg)
                redactNext = "<model>"
            case "-f":
                output.append(arg)
                redactNext = "<audio>"
            case "-p", "--prompt":
                output.append(arg)
                redactNext = "<prompt>"
            default:
                output.append(arg)
            }
        }
        return output.joined(separator: " ")
    }

    private func redactedPath(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "<path>" : name
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
