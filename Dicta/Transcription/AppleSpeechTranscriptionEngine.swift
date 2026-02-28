import Foundation
import Speech

final class AppleSpeechTranscriptionEngine: TranscriptionEngine {
    private let logger: DiagnosticsLogger

    init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.permissionDenied
        }
        let resolvedLocale = resolveLocale(from: locale)
        if resolvedLocale.identifier != locale.identifier {
            logger.log(.transcription, "Requested locale \(locale.identifier) not supported; using \(resolvedLocale.identifier)")
        }
        guard let recognizer = SFSpeechRecognizer(locale: resolvedLocale) else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        if preferOnDevice && !recognizer.supportsOnDeviceRecognition {
            logger.log(.transcription, "On-device recognition not available; falling back to server")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.taskHint = .dictation
        request.shouldReportPartialResults = false
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let taskBox = RecognitionTaskBox()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let resumeBox = SingleResumeBox(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty {
                            resumeBox.resume(throwing: TranscriptionError.noSpeechDetected)
                        } else {
                            let confidence = result.bestTranscription.segments.map { Double($0.confidence) }.reduce(0.0, +) / Double(max(result.bestTranscription.segments.count, 1))
                            let durations = result.bestTranscription.segments.map { $0.duration }
                            resumeBox.resume(returning: TranscriptionResult(text: text, confidence: confidence, segmentDurations: durations))
                        }
                        if let error {
                            self.logger.log(.transcription, "Recognition finished with error: \(error.localizedDescription)")
                        }
                        return
                    }
                    if let error {
                        resumeBox.resume(throwing: self.map(error: error))
                        return
                    }
                }
                taskBox.set(task)
            }
        }, onCancel: {
            taskBox.cancel()
        })
    }

    private func map(error: Error) -> Error {
        let nsError = error as NSError
        // Map some common conditions without relying on private Speech error codes/domains.
        // Network and permission issues are common; otherwise, fall back to underlying.
        let description = nsError.localizedDescription
        let codeInfo = "\(nsError.domain) (\(nsError.code))"
        // Heuristic mapping based on messages Apple emits.
        let lower = description.lowercased()
        if lower.contains("not authorized") || lower.contains("no authorization") || lower.contains("permission") {
            return TranscriptionError.permissionDenied
        }
        if lower.contains("network") || lower.contains("internet") || lower.contains("connection") {
            return TranscriptionError.networkRequired
        }
        if nsError.code == NSUserCancelledError {
            return TranscriptionError.cancelled
        }
        // If recognizer is unavailable, Apple's Speech sometimes reports codes in the Speech domain,
        // but since we are avoiding direct references, fall back to recognizerUnavailable when message hints it.
        if lower.contains("recognizer") && lower.contains("unavailable") {
            return TranscriptionError.recognizerUnavailable
        }
        if lower.contains("on-device") && lower.contains("unsupported") {
            return TranscriptionError.onDeviceUnavailable
        }
        return TranscriptionError.underlying("\(description) [\(codeInfo)]")
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

        if let languageCode = locale.languageCode {
            let preferredRegion = locale.regionCode ?? Locale.current.regionCode
            if let preferredRegion,
               let regionalMatch = supported.first(where: { $0.languageCode == languageCode && $0.regionCode == preferredRegion }) {
                return regionalMatch
            }
            if let languageMatch = supported.first(where: { $0.languageCode == languageCode }) {
                return languageMatch
            }
        }

        if let currentMatch = supported.first(where: { $0.identifier == Locale.current.identifier || $0.identifier == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }) {
            return currentMatch
        }

        return supported.sorted(by: { $0.identifier < $1.identifier }).first ?? locale
    }
}

private final class RecognitionTaskBox {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func set(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        task?.cancel()
        lock.unlock()
    }
}

private final class SingleResumeBox<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
