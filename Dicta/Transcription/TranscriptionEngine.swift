import Foundation
import AVFoundation

protocol TranscriptionEngine {
    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult
    func transcribeFile(url: URL, locale: Locale, prompt: String) async throws -> String
    var supportsStreaming: Bool { get }
    func startStreaming(locale: Locale,
                        contextualStrings: [String],
                        preferOnDevice: Bool,
                        partialHandler: @escaping (String) -> Void,
                        finalHandler: @escaping (String) -> Void,
                        errorHandler: @escaping (Error) -> Void) throws
    func feedAudio(buffer: AVAudioPCMBuffer)
    func stopStreaming() async
    func cancelStreaming()
}

extension TranscriptionEngine {
    var supportsStreaming: Bool { false }

    func transcribeFile(url: URL, locale: Locale, prompt: String) async throws -> String {
        let result = try await transcribe(url: url, locale: locale, preferOnDevice: true)
        return result.text
    }

    func startStreaming(locale: Locale,
                        contextualStrings: [String],
                        preferOnDevice: Bool,
                        partialHandler: @escaping (String) -> Void,
                        finalHandler: @escaping (String) -> Void,
                        errorHandler: @escaping (Error) -> Void) throws {
        throw TranscriptionError.recognizerUnavailable
    }

    func feedAudio(buffer: AVAudioPCMBuffer) {}

    func stopStreaming() async {}

    func cancelStreaming() {}
}

enum TranscriptionError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case networkRequired
    case noSpeechDetected
    case cancelled
    case timeout
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Speech recognition permission denied"
        case .recognizerUnavailable: return "Speech recognizer unavailable"
        case .onDeviceUnavailable: return "On-device recognition not available"
        case .networkRequired: return "Network required for recognition"
        case .noSpeechDetected: return "No speech detected"
        case .cancelled: return "Transcription cancelled"
        case .timeout: return "Transcription timed out"
        case .underlying(let message): return message
        }
    }
}
