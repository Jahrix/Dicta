import Foundation

struct TranscriptionResult {
    let text: String
    let confidence: Double?
    let segmentDurations: [TimeInterval]?
}
