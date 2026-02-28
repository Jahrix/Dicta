import Foundation

enum DictationState: Equatable {
    case idle
    case armed
    case recording(startedAt: Date)
    case stopping
    case transcribing
    case inserting
    case error(String)

    var isBusy: Bool {
        switch self {
        case .idle:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .armed: return "Armed"
        case .recording: return "Recording"
        case .stopping: return "Stopping"
        case .transcribing: return "Transcribing"
        case .inserting: return "Inserting"
        case .error: return "Error"
        }
    }

    var recordingStartedAt: Date? {
        if case .recording(let startedAt) = self { return startedAt }
        return nil
    }
}
