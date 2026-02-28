import Foundation

protocol TranscriptionEngine {
    func transcribe(url: URL, locale: Locale, preferOnDevice: Bool) async throws -> TranscriptionResult
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
