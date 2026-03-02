import AVFoundation
import Foundation

enum AudioFormatConverter {
    static func convertToWhisperWAV(inputURL: URL, logger: DiagnosticsLogger) throws -> URL {
        let inputFile = try AVAudioFile(forReading: inputURL)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: false) else {
            throw NSError(domain: "Dicta.AudioFormatConverter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target WAV format"])
        }
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw NSError(domain: "Dicta.AudioFormatConverter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Dicta/Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let outputURL = tempDir.appendingPathComponent("\(inputURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).wav")
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let inputCapacity = AVAudioFrameCount(max(2048, Int(inputFile.processingFormat.sampleRate / 5)))
        let ratio = outputFormat.sampleRate / inputFile.processingFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * ratio) + 1

        logger.log(.audio, "Converting audio for whisper (input=\(inputURL.lastPathComponent), output=\(outputURL.lastPathComponent))")

        while true {
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inputCapacity) else {
                throw NSError(domain: "Dicta.AudioFormatConverter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate input buffer"])
            }
            try inputFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 {
                break
            }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
                throw NSError(domain: "Dicta.AudioFormatConverter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
            }

            var error: NSError?
            var didProvideInput = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if let error {
                throw error
            }
            guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
                continue
            }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
        }

        return outputURL
    }
}
