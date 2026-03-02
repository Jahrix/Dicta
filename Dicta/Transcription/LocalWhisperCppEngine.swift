import AVFoundation
import Foundation

@MainActor
final class LocalWhisperCppEngine: TranscriptionEngine {
    private let settings: SettingsModel
    private let logger: DiagnosticsLogger
    private static var cachedSupportedFlags: [String: LocalWhisperSupportedFlags] = [:]

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
        let modelURL = try resolveModelURL()
        let timeoutSeconds = settings.transcriptionTimeoutSeconds > 0 ? settings.transcriptionTimeoutSeconds : 45.0
        let supportedFlags = await loadSupportedFlags(binaryPath: binaryPath, timeoutSeconds: min(timeoutSeconds, 12.0))
        let preset = SettingsModel.TranscriptionPreset(rawValue: settings.transcriptionPreset) ?? .accuracy
        let presetDefaults = SettingsModel.presetDefaults(for: preset)
        let threads = max(0, settings.threads)
        let beamSize = settings.beamSize > 0 ? settings.beamSize : presetDefaults.beamSize
        let temperature = settings.temperature >= 0.0 && settings.temperature <= 1.0 ? settings.temperature : presetDefaults.temperature
        let bestOf = settings.bestOf > 0 ? settings.bestOf : presetDefaults.bestOf
        let promptBias = settings.enablePromptBias ? prompt.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let temperatureText = String(format: "%.2f", temperature)

        logger.log(.transcription,
                   "LocalWhisper preset=\(preset.rawValue) beam=\(beamSize) temp=\(temperatureText) bestOf=\(bestOf) threads=\(threads) model=\(redactedPath(modelURL.path)) binary=\(redactedPath(binaryPath)) locale=\(locale.identifier)")

        let convertedURL: URL
        do {
            convertedURL = try AudioFormatConverter.convertToWhisperWAV(inputURL: url, logger: logger)
        } catch {
            let message = "Local ASR unavailable: WAV conversion failed. \(error.localizedDescription)"
            logger.log(.transcription, message)
            throw TranscriptionError.underlying(message)
        }
        defer { try? FileManager.default.removeItem(at: convertedURL) }

        let argsBuilder = WhisperCLIArgs(modelURL: modelURL,
                                         wavURL: convertedURL,
                                         languageCode: normalizedLanguageCode(locale: locale),
                                         beamSize: beamSize,
                                         temperature: temperature,
                                         bestOf: bestOf,
                                         threads: threads,
                                         prompt: promptBias,
                                         supportedFlags: supportedFlags)
        let arguments = argsBuilder.makeArguments()
        logger.log(.transcription, "LocalWhisper args: \(argsBuilder.redactedDescription)")

        var lastProcessError: String?
        for attempt in 1...2 {
            do {
                let transcript = try await runWhisper(binaryPath: binaryPath,
                                                      arguments: arguments,
                                                      timeoutSeconds: timeoutSeconds)
                return transcript
            } catch let LocalWhisperProcessError.nonZeroExit(code, stderr, stdout) {
                lastProcessError = "exit=\(code) stderr=\(stderr) stdout=\(stdout)"
                logger.log(.transcription, "LocalWhisper non-zero exit on attempt \(attempt): \(lastProcessError!)")
                if attempt == 2 {
                    throw TranscriptionError.underlying("Local whisper failed after retry (code \(code)). \(stderr)")
                }
            } catch {
                throw error
            }
        }

        throw TranscriptionError.underlying(lastProcessError ?? "Local whisper failed after retry")
    }

    private func runWhisper(binaryPath: String, arguments: [String], timeoutSeconds: Double) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
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
                    throw LocalWhisperProcessError.nonZeroExit(code: Int(process.terminationStatus),
                                                               stderr: Self.tail(rawStderr, maxChars: 600),
                                                               stdout: Self.tail(rawStdout, maxChars: 200))
                }
                return try Self.parseTranscript(from: rawStdout)
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
        let overridePath = settings.whisperBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overridePath.isEmpty, FileManager.default.isExecutableFile(atPath: overridePath) {
            return overridePath
        }

        let candidatePaths = [
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/whisper"
        ]
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        for command in ["whisper-cpp", "whisper"] {
            if let path = resolveUsingWhich(command: command) {
                return path
            }
        }

        let fixPath = appSupportModelsDirectory().path
        let message = "Local ASR unavailable: missing binary/model. Fix: brew install whisper-cpp, download ggml-small.en.bin to \(fixPath)"
        logger.log(.transcription, message)
        throw TranscriptionError.underlying(message)
    }

    private func resolveModelURL() throws -> URL {
        let fileManager = FileManager.default
        let overridePath = settings.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overridePath.isEmpty, fileManager.fileExists(atPath: overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        let presetDefaults = SettingsModel.presetDefaults(for: SettingsModel.TranscriptionPreset(rawValue: settings.transcriptionPreset) ?? .accuracy)
        let preferredTier = settings.selectedModelTier
        let fallbackTier = presetDefaults.modelTier
        let preferredNames = uniqueModelNames(for: [preferredTier, fallbackTier, .small, .base, .tiny])

        let appSupportDirectory = appSupportModelsDirectory()
        for name in preferredNames {
            let candidate = appSupportDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let candidate = firstModel(in: appSupportDirectory) {
            return candidate
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundledModels = resourceURL.appendingPathComponent("models", isDirectory: true)
            for name in preferredNames {
                let candidate = bundledModels.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let candidate = firstModel(in: bundledModels) {
                return candidate
            }
        }

        let message = "Local ASR unavailable: missing binary/model. Fix: brew install whisper-cpp, download ggml-small.en.bin to \(appSupportDirectory.path)"
        logger.log(.transcription, message)
        throw TranscriptionError.underlying(message)
    }

    private func resolveUsingWhich(command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    private func loadSupportedFlags(binaryPath: String, timeoutSeconds: Double) async -> LocalWhisperSupportedFlags {
        if let cached = Self.cachedSupportedFlags[binaryPath] {
            return cached
        }

        let helpOutput = await readHelpOutput(binaryPath: binaryPath, timeoutSeconds: timeoutSeconds)
        let lower = helpOutput.lowercased()
        let supported = LocalWhisperSupportedFlags(
            beamSizeFlag: lower.contains("--beam-size") ? "--beam-size" : (lower.contains("--beam_size") ? "--beam_size" : (lower.contains("\n-b") ? "-b" : nil)),
            temperatureFlag: lower.contains("--temperature") ? "--temperature" : nil,
            bestOfFlag: lower.contains("--best-of") ? "--best-of" : (lower.contains("--best_of") ? "--best_of" : nil),
            languageFlag: lower.contains("--language") ? "--language" : (lower.contains("\n-l") ? "-l" : nil),
            promptFlag: lower.contains("--prompt") ? "--prompt" : (lower.contains("\n-p") ? "-p" : nil),
            noTimestampsFlag: lower.contains("-nt") || lower.contains("--no-timestamps") ? (lower.contains("--no-timestamps") ? "--no-timestamps" : "-nt") : nil,
            threadsFlag: lower.contains("--threads") ? "--threads" : (lower.contains("\n-t ") ? "-t" : nil)
        )
        Self.cachedSupportedFlags[binaryPath] = supported
        return supported
    }

    private func readHelpOutput(binaryPath: String, timeoutSeconds: Double) async -> String {
        for args in [["--help"], ["-h"]] {
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
        return ""
    }

    private func appSupportModelsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Dicta/models", isDirectory: true)
    }

    private func firstModel(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else {
            return nil
        }
        return contents
            .filter { $0.pathExtension == "bin" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    private func uniqueModelNames(for tiers: [SpeechModelTier]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for tier in tiers {
            let filename = tier.defaultModelFilename
            if seen.insert(filename).inserted {
                ordered.append(filename)
            }
        }
        return ordered
    }

    private func normalizedLanguageCode(locale: Locale) -> String {
        let configured = settings.languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }
        return locale.language.languageCode?.identifier
            ?? (locale as NSLocale).object(forKey: .languageCode) as? String
            ?? "en"
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

    private static func parseTranscript(from stdout: String) throws -> String {
        let lines = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("[") }
        let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }
        return joined.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func tail(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -maxChars)
        return "…\(trimmed[start...])"
    }
}
