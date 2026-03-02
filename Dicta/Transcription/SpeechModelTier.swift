import Foundation

enum SpeechModelTier: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case medium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        }
    }

    var shortDescription: String {
        switch self {
        case .tiny:
            return "Quick transcription, good for short phrases."
        case .base:
            return "Best balance of speed and accuracy."
        case .small:
            return "Better accuracy, slower transcription."
        case .medium:
            return "Best accuracy, slowest transcription."
        }
    }

    var defaultModelFilename: String {
        switch self {
        case .tiny:
            return "ggml-tiny.en.bin"
        case .base:
            return "ggml-base.en.bin"
        case .small:
            return "ggml-small.en.bin"
        case .medium:
            return "ggml-medium.en.bin"
        }
    }
}
