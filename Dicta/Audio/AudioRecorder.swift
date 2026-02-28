import Foundation
import AVFoundation

struct AudioRecorderStats: Sendable {
    let framesReceived: Int64
    let bytesWritten: Int64
    let peakRMS: Double
    let currentRMS: Double
    let lastNonSilentAt: Date?
    let lastFrameAt: Date?
    let startTime: Date?
    let sampleRate: Double
    let channels: Int
}

struct RecordingInfo {
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let fileSizeBytes: UInt64
    let stats: AudioRecorderStats
}

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var converter: AVAudioConverter?
    private let sessionGuard = AudioSessionGuard()
    private let logger: DiagnosticsLogger
    var onConfigurationChange: (() -> Void)?
    var vadThresholdRMS: Double = 0.015

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let statsLock = NSLock()
    private var stats = AudioRecorderStats(framesReceived: 0,
                                          bytesWritten: 0,
                                          peakRMS: 0,
                                          currentRMS: 0,
                                          lastNonSilentAt: nil,
                                          lastFrameAt: nil,
                                          startTime: nil,
                                          sampleRate: 16_000,
                                          channels: 1)
    private var lastTapLogAt: Date?
    private var lastNonSilentLogAt: Date?
    private var didLogMissingInt16 = false
    private var didLogMissingFloat = false

    init(logger: DiagnosticsLogger) {
        self.logger = logger
        sessionGuard.onConfigurationChange = { [weak self] in
            self?.logger.log(.audio, "Audio engine configuration changed")
            self?.onConfigurationChange?()
        }
    }

    func startRecording() throws -> URL {
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        let url = Self.makeRecordingURL()
        audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
        recordingURL = url
        startTime = Date()
        resetStats(sampleRate: targetFormat.sampleRate, channels: Int(targetFormat.channelCount))

        sessionGuard.start()
        logger.log(.audio, "Recording to \(url.path)")

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let audioFile = self.audioFile else { return }
            self.markFramesReceived(frameCount: Int(buffer.frameLength))
            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputFrameCapacity) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                self.logger.log(.audio, "Conversion error: \(error.localizedDescription)")
                return
            }
            do {
                try audioFile.write(from: convertedBuffer)
                self.updateStats(with: convertedBuffer)
            } catch {
                self.logger.log(.audio, "Write error: \(error.localizedDescription)")
            }
        }

        engine.prepare()
        try engine.start()
        return url
    }

    func stopRecording(trimSilence: Bool = true) async throws -> RecordingInfo {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sessionGuard.stop()

        guard let url = recordingURL else {
            throw RecordingError.missingFile
        }

        if trimSilence {
            try? trimTrailingSilence(url: url)
        }

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let snapshot = currentStats()
        let info = RecordingInfo(url: url, duration: duration, sampleRate: targetFormat.sampleRate, fileSizeBytes: fileSize, stats: snapshot)
        logger.log(.audio, "Stopped recording (duration: \(String(format: "%.2f", duration))s, sampleRate: \(targetFormat.sampleRate), frames: \(snapshot.framesReceived), bytes: \(snapshot.bytesWritten), peakRMS: \(String(format: "%.4f", snapshot.peakRMS)), fileSize: \(fileSize))")
        cleanupState()
        return info
    }

    func cancelRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sessionGuard.stop()

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupState()
    }

    private func cleanupState() {
        audioFile = nil
        recordingURL = nil
        startTime = nil
        converter = nil
    }

    private func trimTrailingSilence(url: URL, threshold: Int16 = 500) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        try file.read(into: buffer)

        guard let channelData = buffer.int16ChannelData else { return }
        let samples = channelData[0]
        var lastNonSilent = -1
        if buffer.frameLength > 0 {
            for i in stride(from: Int(buffer.frameLength) - 1, through: 0, by: -1) {
                if abs(samples[i]) > threshold {
                    lastNonSilent = i
                    break
                }
            }
        }
        guard lastNonSilent >= 0 else { return }

        let newLength = AVAudioFrameCount(lastNonSilent + 1)
        if newLength == buffer.frameLength { return }

        buffer.frameLength = newLength
        let trimmedURL = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-trimmed.caf")
        let outFile = try AVAudioFile(forWriting: trimmedURL, settings: format.settings)
        try outFile.write(from: buffer)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: trimmedURL, to: url)
        logger.log(.audio, "Trimmed trailing silence")
    }

    private static func makeRecordingURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dicta", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Dicta-\(formatter.string(from: Date())).caf"
        return dir.appendingPathComponent(name)
    }

    func currentStats() -> AudioRecorderStats {
        statsLock.lock()
        let snapshot = stats
        statsLock.unlock()
        return snapshot
    }

    private func resetStats(sampleRate: Double, channels: Int) {
        statsLock.lock()
        stats = AudioRecorderStats(framesReceived: 0,
                                   bytesWritten: 0,
                                   peakRMS: 0,
                                   currentRMS: 0,
                                   lastNonSilentAt: nil,
                                   lastFrameAt: nil,
                                   startTime: Date(),
                                   sampleRate: sampleRate,
                                   channels: channels)
        lastTapLogAt = nil
        lastNonSilentLogAt = nil
        statsLock.unlock()
    }

    private func markFramesReceived(frameCount: Int) {
        guard frameCount > 0 else { return }
        let now = Date()
        statsLock.lock()
        let newFrames = stats.framesReceived + Int64(frameCount)
        stats = AudioRecorderStats(framesReceived: newFrames,
                                   bytesWritten: stats.bytesWritten,
                                   peakRMS: stats.peakRMS,
                                   currentRMS: stats.currentRMS,
                                   lastNonSilentAt: stats.lastNonSilentAt,
                                   lastFrameAt: now,
                                   startTime: stats.startTime,
                                   sampleRate: stats.sampleRate,
                                   channels: stats.channels)
        statsLock.unlock()
    }

    private func updateStats(with buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let bytesPerFrame = Int64(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let rms = computeRMS(buffer: buffer, frameLength: frameLength)

        let now = Date()
        statsLock.lock()
        let newFrames = stats.framesReceived
        let newBytes = stats.bytesWritten + (Int64(frameLength) * bytesPerFrame)
        let newPeak = max(stats.peakRMS, rms)
        let isNonSilent = rms >= vadThresholdRMS
        let lastNonSilentAt = isNonSilent ? now : stats.lastNonSilentAt
        stats = AudioRecorderStats(framesReceived: newFrames,
                                   bytesWritten: newBytes,
                                   peakRMS: newPeak,
                                   currentRMS: rms,
                                   lastNonSilentAt: lastNonSilentAt,
                                   lastFrameAt: now,
                                   startTime: stats.startTime,
                                   sampleRate: stats.sampleRate,
                                   channels: stats.channels)
        let shouldLog = lastTapLogAt.map { now.timeIntervalSince($0) > 1.0 } ?? true
        if shouldLog {
            lastTapLogAt = now
            logger.log(.audio, "Audio tap frames=\(newFrames) bytes=\(newBytes) rms=\(String(format: "%.4f", rms)) peakRMS=\(String(format: "%.4f", newPeak)) threshold=\(String(format: "%.4f", vadThresholdRMS))", verbose: true)
        }
        if isNonSilent {
            let shouldLogNonSilent = lastNonSilentLogAt.map { now.timeIntervalSince($0) > 1.0 } ?? true
            if shouldLogNonSilent {
                lastNonSilentLogAt = now
                logger.log(.audio, "VAD non-silent detected (rms=\(String(format: "%.4f", rms)))", verbose: true)
            }
        }
        statsLock.unlock()
    }

    private func computeRMS(buffer: AVAudioPCMBuffer, frameLength: Int) -> Double {
        if let data = buffer.int16ChannelData {
            var sum: Double = 0
            let samples = data[0]
            for i in 0..<frameLength {
                let sample = Double(samples[i])
                sum += sample * sample
            }
            return sqrt(sum / Double(frameLength)) / 32768.0
        }

        if !didLogMissingInt16 {
            didLogMissingInt16 = true
            logger.log(.audio, "int16ChannelData unavailable; falling back to float/audioBufferList RMS", verbose: true)
        }

        if let floatData = buffer.floatChannelData {
            var sum: Double = 0
            let samples = floatData[0]
            for i in 0..<frameLength {
                let sample = Double(samples[i])
                sum += sample * sample
            }
            return sqrt(sum / Double(frameLength))
        }

        if !didLogMissingFloat {
            didLogMissingFloat = true
            logger.log(.audio, "floatChannelData unavailable; falling back to audioBufferList RMS", verbose: true)
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        var sum: Double = 0
        var totalSamples = 0

        for audioBuffer in bufferList {
            guard let mData = audioBuffer.mData else { continue }
            let byteCount = Int(audioBuffer.mDataByteSize)
            if byteCount == 0 { continue }

            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let sampleCount = byteCount / MemoryLayout<Float>.size
                let samples = mData.assumingMemoryBound(to: Float.self)
                for i in 0..<sampleCount {
                    let sample: Double = Double(samples[i])
                    sum += sample * sample
                }
                totalSamples += sampleCount
            default:
                let sampleCount = byteCount / MemoryLayout<Int16>.size
                let samples = mData.assumingMemoryBound(to: Int16.self)
                for i in 0..<sampleCount {
                    let sample: Double = Double(samples[i])
                    sum += sample * sample
                }
                totalSamples += sampleCount
            }
        }

        guard totalSamples > 0 else { return 0 }

        let rms = sqrt(sum / Double(totalSamples))
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            return rms
        }
        return rms / 32768.0
    }
}

enum RecordingError: Error {
    case missingFile
}
