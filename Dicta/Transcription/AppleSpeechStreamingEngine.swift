import Foundation
import Speech
import AVFoundation

final class AppleSpeechStreamingEngine: TranscriptionEngine {
    private let logger: DiagnosticsLogger
    private let settings: SettingsModel
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var partialHandler: ((String) -> Void)?
    private var finalHandler: ((String) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    init(settings: SettingsModel, logger: DiagnosticsLogger) {
        self.settings = settings
        self.logger = logger
    }

    var supportsStreaming: Bool { true }

    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult {
        throw TranscriptionError.underlying("Streaming engine does not support file transcription")
    }

    func startStreaming(locale: Locale,
                        contextualStrings: [String],
                        preferOnDevice: Bool,
                        partialHandler: @escaping (String) -> Void,
                        finalHandler: @escaping (String) -> Void,
                        errorHandler: @escaping (Error) -> Void) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.permissionDenied
        }
        let resolvedLocale = resolveLocale(from: locale)
        if resolvedLocale.identifier != locale.identifier {
            logger.log(.transcription, "Requested locale \(locale.identifier) not supported; using \(resolvedLocale.identifier)")
        }
        logger.log(.transcription, "Streaming start (locale: \(resolvedLocale.identifier), preferOnDevice: \(preferOnDevice))")
        guard let recognizer = SFSpeechRecognizer(locale: resolvedLocale) else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        if preferOnDevice && !recognizer.supportsOnDeviceRecognition {
            logger.log(.transcription, "On-device recognition not available; falling back to server")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let cappedContext = Array(contextualStrings.prefix(50))
        if !cappedContext.isEmpty {
            request.contextualStrings = cappedContext
            logger.log(.transcription, "Streaming contextual strings loaded (\(cappedContext.count))", verbose: true)
        }

        self.recognizer = recognizer
        self.request = request
        self.partialHandler = partialHandler
        self.finalHandler = finalHandler
        self.errorHandler = errorHandler

        task?.cancel()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.logger.log(.transcription, "Streaming final result (length: \(text.count))")
                    self.finalHandler?(text)
                } else {
                    self.partialHandler?(text)
                }
            }
            if let error {
                self.logger.log(.transcription, "Streaming error: \(error.localizedDescription)")
                self.errorHandler?(self.map(error: error))
            }
        }
    }

    func feedAudio(buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stopStreaming() async {
        request?.endAudio()
    }

    func cancelStreaming() {
        task?.cancel()
        request = nil
        recognizer = nil
        partialHandler = nil
        finalHandler = nil
        errorHandler = nil
    }

    private func resolveLocale(from locale: Locale) -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        if supported.contains(locale) {
            return locale
        }

        let identifier = locale.identifier
        if identifier.contains("_") {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            let normalizedLocale = Locale(identifier: normalized)
            if supported.contains(normalizedLocale) {
                return normalizedLocale
            }
        }

        let languageCode = extractLanguageCode(from: locale)
        if let languageCode {
            let preferredRegion = extractRegionCode(from: locale) ?? extractRegionCode(from: Locale.current)
            if let preferredRegion {
                if let regionalMatch = supported.first(where: {
                    extractLanguageCode(from: $0) == languageCode && extractRegionCode(from: $0) == preferredRegion
                }) {
                    return regionalMatch
                }
            }
            if let languageMatch = supported.first(where: { extractLanguageCode(from: $0) == languageCode }) {
                return languageMatch
            }
        }

        if let currentMatch = supported.first(where: { $0.identifier == Locale.current.identifier || $0.identifier == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }) {
            return currentMatch
        }

        return supported.sorted(by: { $0.identifier < $1.identifier }).first ?? locale
    }

    private func extractLanguageCode(from locale: Locale) -> String? {
        locale.language.languageCode?.identifier
    }

    private func extractRegionCode(from locale: Locale) -> String? {
        locale.region?.identifier
    }

    private func map(error: Error) -> Error {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        let lower = description.lowercased()
        if lower.contains("not authorized") || lower.contains("permission") {
            return TranscriptionError.permissionDenied
        }
        if lower.contains("network") || lower.contains("internet") || lower.contains("connection") {
            return TranscriptionError.networkRequired
        }
        if nsError.code == NSUserCancelledError {
            return TranscriptionError.cancelled
        }
        if lower.contains("recognizer") && lower.contains("unavailable") {
            return TranscriptionError.recognizerUnavailable
        }
        if lower.contains("on-device") && lower.contains("unsupported") {
            return TranscriptionError.onDeviceUnavailable
        }
        return TranscriptionError.underlying("\(description) [\(nsError.domain) (\(nsError.code))]")
    }
}
