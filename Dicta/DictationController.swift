import Foundation
import Combine
import AppKit
import AVFoundation

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastError: String = ""

    private let settings: SettingsModel
    private let permissions: PermissionsManager
    private let logger: DiagnosticsLogger

    private let audioRecorder: AudioRecorder
    private let transcriptionEngine: TranscriptionEngine
    private let streamingEngine: TranscriptionEngine
    private let insertionManager: InsertionManager
    private let hudController = HUDController()
    private var currentRecordingURL: URL?
    private var lastRecordingInfo: RecordingInfo?
    private var lastTranscriptionDuration: TimeInterval?
    private var lastTranscriptionErrorDetails: String = "none"
    private var lastInsertionMode: String = "none"
    private var lastInsertionResult: String = "none"
    private var transcriptionTask: Task<Void, Never>?
    private var insertionTask: Task<Void, Never>?
    private var maxRecordingTask: Task<Void, Never>?
    private var startRecordingTask: Task<Void, Never>?
    private var streamingFinalText: String?
    private var streamingFailed: Bool = false
    private var streamingFinalContinuation: CheckedContinuation<String?, Never>?
    private var lastPartialHUDUpdate = Date.distantPast
    private var lastPartialText: String = ""
    private var startRequestID: UUID?
    private let watchdogQueue = DispatchQueue(label: "com.dicta.watchdog", qos: .utility)
    private var watchdogTimer: DispatchSourceTimer?
    private var noFramesTask: Task<Void, Never>?
    private var stateEnteredAt = Date()
    private var isStopping = false

    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsModel, permissions: PermissionsManager, logger: DiagnosticsLogger) {
        self.settings = settings
        self.permissions = permissions
        self.logger = logger
        self.audioRecorder = AudioRecorder(logger: logger)
        self.transcriptionEngine = AppleSpeechTranscriptionEngine(settings: settings, logger: logger)
        self.streamingEngine = AppleSpeechStreamingEngine(settings: settings, logger: logger)
        self.insertionManager = InsertionManager(
            pasteboardInserter: PasteboardInserter(logger: logger),
            accessibilityInserter: AccessibilityTyperInserter(logger: logger),
            logger: logger
        )

        audioRecorder.onConfigurationChange = { [weak self] in
            Task { @MainActor in
                self?.handleAudioConfigurationChange()
            }
        }

        audioRecorder.vadThresholdRMS = settings.vadThresholdRMS

        settings.$verboseLogging
            .sink { [weak self] enabled in
                self?.logger.verboseEnabled = enabled
            }
            .store(in: &cancellables)

        settings.$vadThresholdRMS
            .sink { [weak self] value in
                self?.audioRecorder.vadThresholdRMS = value
            }
            .store(in: &cancellables)

        settings.$showHUD
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateHUD(for: self.state)
            }
            .store(in: &cancellables)

        startWatchdog()
    }

    func toggleDictation() {
        logger.log(.state, "Toggle requested in state \(state.displayName)")
        switch state {
        case .idle:
            startRecordingFlow()
        case .armed:
            cancelAndReset(reason: "Cancelled while arming")
        case .recording:
            stopRecordingFlow(reason: "User stopped recording")
        case .stopping, .transcribing, .inserting:
            cancelAndReset(reason: "User cancelled")
        case .error:
            transition(to: .idle, reason: "Reset after error")
        }
    }

    func insert(text: String) async throws {
        try await insertionManager.insert(text: text,
                                          mode: settings.insertionMode,
                                          restoreClipboard: settings.restoreClipboard)
    }

    private func startRecordingFlow() {
        lastError = ""
        lastTranscriptionErrorDetails = "none"
        lastInsertionMode = "none"
        lastInsertionResult = "none"
        startRecordingTask?.cancel()
        let requestID = UUID()
        startRequestID = requestID
        transition(to: .armed, reason: "Starting dictation")
        updateHUD(for: .armed)
        NSSound.beep()

        startRecordingTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.ensurePermissionsAndStartRecording(requestID: requestID)
        }
    }

    private func ensurePermissionsAndStartRecording(requestID: UUID) async {
        var micStatus = permissions.microphoneStatus()
        if micStatus == .notDetermined {
            micStatus = await permissions.requestMicrophone()
        }
        guard micStatus == .granted else {
            await MainActor.run {
                self.fail("Microphone permission not granted")
            }
            return
        }

        var speechStatus = permissions.speechStatus()
        if speechStatus == .notDetermined {
            speechStatus = await permissions.requestSpeech()
        }
        guard speechStatus == .granted else {
            await MainActor.run {
                self.fail("Speech recognition permission not granted")
            }
            return
        }

        let shouldProceed = await MainActor.run { [weak self] in
            guard let self else { return false }
            return self.startRequestID == requestID && (self.state == .armed || self.state == .idle)
        }
        guard shouldProceed else { return }

        do {
            let url = try audioRecorder.startRecording()
            await MainActor.run {
                self.currentRecordingURL = url
                self.lastRecordingInfo = nil
                self.transition(to: .recording(startedAt: Date()), reason: "Recording started")
                self.startMaxRecordingTimer()
                self.startNoFramesCheck()
                self.startStreamingSession()
                self.updateHUD(for: self.state)
            }
        } catch {
            await MainActor.run {
                self.fail("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    private func handleAudioConfigurationChange() {
        switch state {
        case .recording, .armed, .stopping:
            cancelAndReset(reason: "Audio device changed or interrupted")
        default:
            fail("Audio device changed or interrupted")
        }
    }

    private func stopRecordingFlow(reason: String) {
        guard case .recording = state else {
            logger.log(.state, "Stop recording ignored (state: \(state.displayName))")
            return
        }
        guard !isStopping else {
            logger.log(.state, "Stop recording ignored (already stopping)")
            return
        }
        isStopping = true
        maxRecordingTask?.cancel()
        noFramesTask?.cancel()
        logger.log(.audio, "Stop recording requested: \(reason)")
        transition(to: .stopping, reason: reason)
        updateHUD(for: .stopping)
        NSSound.beep()

        let languageIdentifier = settings.languageIdentifier
        let preferOnDevice = settings.preferOnDevice
        let transcriptionTimeout = settings.transcriptionTimeoutSeconds > 0 ? settings.transcriptionTimeoutSeconds : 20.0
        let useStreaming = streamingEngine.supportsStreaming

        transcriptionTask?.cancel()
        transcriptionTask = Task.detached { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isStopping = false
                }
            }
            do {
                if useStreaming {
                    await self.streamingEngine.stopStreaming()
                }
                let recordingInfo = try await self.audioRecorder.stopRecording()
                DiagnosticsManager.shared.addRecentAudio(recordingInfo.url)
                self.logger.log(.audio, "Stop recording finished (file: \(recordingInfo.url.lastPathComponent), duration: \(String(format: "%.2f", recordingInfo.duration))s, bytes: \(recordingInfo.fileSizeBytes), frames: \(recordingInfo.stats.framesReceived))")
                await MainActor.run {
                    self.currentRecordingURL = nil
                    self.lastRecordingInfo = recordingInfo
                    self.transition(to: .transcribing, reason: "Recording stopped")
                    self.updateHUD(for: .transcribing)
                }
                if recordingInfo.stats.framesReceived == 0 || recordingInfo.fileSizeBytes == 0 {
                    await MainActor.run {
                        self.fail("Empty audio file (no frames captured)")
                    }
                    return
                }
                var streamingFinal: String?
                var shouldUseStreaming = false
                if useStreaming {
                    streamingFinal = await self.waitForStreamingFinal(timeout: 2.0)
                    shouldUseStreaming = await MainActor.run { !self.streamingFailed }
                }
                if let streamingFinal, shouldUseStreaming {
                    self.logger.log(.transcription, "Using streaming final transcript (length: \(streamingFinal.count))")
                    await MainActor.run {
                        self.handleTranscriptionSuccess(TranscriptionResult(text: streamingFinal, confidence: nil, segmentDurations: nil))
                    }
                    return
                }
                await self.performTranscription(url: recordingInfo.url,
                                                languageIdentifier: languageIdentifier,
                                                preferOnDevice: preferOnDevice,
                                                timeout: transcriptionTimeout)
            } catch {
                await MainActor.run {
                    self.fail("Recording error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performTranscription(url: URL, languageIdentifier: String, preferOnDevice: Bool, timeout: Double) async {
        do {
            logger.log(.transcription, "Transcription started for \(url.lastPathComponent) (locale: \(languageIdentifier), preferOnDevice: \(preferOnDevice))")
            let locale = Locale(identifier: languageIdentifier)
            let start = Date()
            let rawText = try await withTimeout(seconds: timeout, timeoutError: TranscriptionError.timeout) {
                try await self.transcriptionEngine.transcribeFile(url: url,
                                                                 locale: locale,
                                                                 prompt: self.settings.customPrompt)
            }
            let duration = Date().timeIntervalSince(start)
            await MainActor.run {
                self.lastTranscriptionDuration = duration
                self.lastTranscriptionErrorDetails = "none"
            }
            logger.log(.transcription, "Transcription finished (length: \(rawText.count))")
            await MainActor.run {
                self.handleTranscriptionSuccess(TranscriptionResult(text: rawText, confidence: nil, segmentDurations: nil))
            }
        } catch {
            if Task.isCancelled {
                logger.log(.transcription, "Transcription cancelled")
                return
            }
            let details = Self.detailedErrorDescription(error)
            logger.log(.transcription, "Transcription failed: \(details)")
            await MainActor.run {
                self.lastTranscriptionErrorDetails = details
                self.fail("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleTranscriptionSuccess(_ result: TranscriptionResult) {
        let rawText = result.text
        logger.log(.transcription, "Transcript (raw): \(rawText)", verbose: true)
        let processedText = TextPostProcessor.process(rawText, settings: settings)
        logger.log(.transcription, "Transcript (post): \(processedText)", verbose: true)
        guard !processedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            lastTranscriptionErrorDetails = "No speech detected"
            lastInsertionMode = settings.insertionMode.rawValue
            lastInsertionResult = "skipped: no speech detected"
            fail("No speech detected")
            return
        }
        lastTranscript = processedText
        transition(to: .inserting, reason: "Transcription complete")
        updateHUD(for: .inserting)

        let insertionMode = settings.insertionMode
        let restoreClipboard = settings.restoreClipboard
        let insertionTimeout = settings.insertionTimeoutSeconds
        lastInsertionMode = insertionMode.rawValue
        lastInsertionResult = "pending"

        insertionTask?.cancel()
        insertionTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                self.logger.log(.insertion, "Insertion started (mode: \(insertionMode.rawValue), chars: \(processedText.count))")
                try await self.withTimeout(seconds: insertionTimeout, timeoutError: InsertionError.timeout) {
                    try await self.insertionManager.insert(text: processedText,
                                                          mode: insertionMode,
                                                          restoreClipboard: restoreClipboard)
                }
                await MainActor.run {
                    self.lastInsertionResult = "success"
                    self.transition(to: .idle, reason: "Insertion complete")
                    self.updateHUD(for: .idle)
                }
                self.logger.log(.insertion, "Insertion completed successfully")
            } catch {
                if Task.isCancelled {
                    self.logger.log(.insertion, "Insertion cancelled")
                    return
                }
                let details = Self.detailedErrorDescription(error)
                await MainActor.run {
                    let message = "Insertion failed: \(error.localizedDescription)"
                    self.lastInsertionResult = "failed: \(details)"
                    self.fail(message)
                    NotificationPresenter.shared.notify(title: "Dicta Insert Failed", body: message)
                }
                self.logger.log(.insertion, "Insertion failed: \(details)")
            }
        }
    }

    private func cancelAndReset(reason: String) {
        logger.log(.state, "Cancel: \(reason)")
        isStopping = false
        startRecordingTask?.cancel()
        startRequestID = nil
        transcriptionTask?.cancel()
        insertionTask?.cancel()
        maxRecordingTask?.cancel()
        noFramesTask?.cancel()
        audioRecorder.cancelRecording()
        streamingEngine.cancelStreaming()
        currentRecordingURL = nil
        transition(to: .idle, reason: "Cancelled")
        updateHUD(for: .idle)
    }

    private func transition(to newState: DictationState, reason: String) {
        logger.log(.state, "State \(state.displayName) → \(newState.displayName) (\(reason))")
        state = newState
        stateEnteredAt = Date()
    }

    private func fail(_ message: String) {
        lastError = message
        transition(to: .error(message), reason: message)
        updateHUD(for: .error(message))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if case .error = self.state {
                self.transition(to: .idle, reason: "Auto reset after error")
                self.updateHUD(for: .idle)
            }
        }
    }

    private func startStreamingSession() {
        streamingFailed = false
        streamingFinalText = nil
        streamingFinalContinuation = nil
        lastPartialText = ""
        lastPartialHUDUpdate = Date.distantPast

        let locale = Locale(identifier: settings.languageIdentifier)
        let contextualStrings = PhraseMapStore.contextualStrings(settings: settings)
        do {
            try streamingEngine.startStreaming(locale: locale,
                                               contextualStrings: contextualStrings,
                                               preferOnDevice: settings.preferOnDevice,
                                               partialHandler: { [weak self] text in
                                                   Task { @MainActor in
                                                       self?.handleStreamingPartial(text)
                                                   }
                                               },
                                               finalHandler: { [weak self] text in
                                                   Task { @MainActor in
                                                       self?.handleStreamingFinal(text)
                                                   }
                                               },
                                               errorHandler: { [weak self] error in
                                                   Task { @MainActor in
                                                       self?.handleStreamingError(error)
                                                   }
                                               })
            logger.log(.transcription, "Streaming started")
            audioRecorder.onAudioBuffer = { [weak self] buffer in
                self?.streamingEngine.feedAudio(buffer: buffer)
            }
        } catch {
            streamingFailed = true
            logger.log(.transcription, "Streaming start failed: \(error.localizedDescription)")
        }
    }

    private func handleStreamingPartial(_ text: String) {
        guard case .recording = state else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        if now.timeIntervalSince(lastPartialHUDUpdate) < 0.12, trimmed == lastPartialText {
            return
        }
        lastPartialHUDUpdate = now
        lastPartialText = trimmed
        logger.log(.transcription, "Streaming partial (length: \(trimmed.count))", verbose: true)
        hudController.show(text: trimmed, mode: .listening)
    }

    private func handleStreamingFinal(_ text: String) {
        streamingFinalText = text
        streamingFinalContinuation?.resume(returning: text)
        streamingFinalContinuation = nil
    }

    private func handleStreamingError(_ error: Error) {
        streamingFailed = true
        let details = Self.detailedErrorDescription(error)
        logger.log(.transcription, "Streaming error: \(details)")
    }

    private func waitForStreamingFinal(timeout: Double) async -> String? {
        if let streamingFinalText { return streamingFinalText }
        return await withCheckedContinuation { continuation in
            streamingFinalContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.streamingFinalContinuation != nil {
                    self.streamingFinalContinuation?.resume(returning: nil)
                    self.streamingFinalContinuation = nil
                }
            }
        }
    }

    private func startMaxRecordingTimer() {
        maxRecordingTask?.cancel()
        let seconds = settings.maxRecordingSeconds
        maxRecordingTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await self?.handleMaxRecordingTimeout()
        }
    }

    private func startNoFramesCheck() {
        noFramesTask?.cancel()
        let timeout = settings.noFramesTimeoutSeconds
        noFramesTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.handleNoFramesTimeout()
        }
    }

    private func startWatchdog() {
        watchdogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.1, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.runWatchdogTick()
            }
        }
        watchdogTimer = timer
        timer.resume()
    }

    private func handleMaxRecordingTimeout() {
        guard case .recording = state else { return }
        stopRecordingFlow(reason: "Max recording length reached")
    }

    private func handleNoFramesTimeout() {
        guard case .recording = state else { return }
        let stats = audioRecorder.currentStats()
        if stats.framesReceived == 0 {
            audioRecorder.cancelRecording()
            fail("No audio frames captured (mic permission/device?)")
        }
    }

    private func runWatchdogTick() {
        if case .recording(let startedAt) = state {
            if isStopping { return }
            let maxAllowed = settings.maxRecordingSeconds + 5
            if stateDuration() > maxAllowed {
                fail("Watchdog: recording timeout")
                return
            }
            let stats = audioRecorder.currentStats()
            if settings.showHUD && settings.verboseLogging {
                let rmsText = String(format: "%.4f", stats.currentRMS)
                let peakText = String(format: "%.4f", stats.peakRMS)
                let thresholdText = String(format: "%.4f", settings.vadThresholdRMS)
                hudController.show(text: "Listening… RMS \(rmsText) • Peak \(peakText) • Th \(thresholdText)", mode: .listening)
            }
            let grace = settings.vadGraceSeconds
            if Date().timeIntervalSince(startedAt) < grace { return }
            let lastNonSilentAt = stats.lastNonSilentAt ?? startedAt
            let silenceThreshold = settings.silenceTimeoutSeconds
            if Date().timeIntervalSince(lastNonSilentAt) > silenceThreshold {
                let rmsText = String(format: "%.4f", stats.currentRMS)
                let peakText = String(format: "%.4f", stats.peakRMS)
                let silenceText = String(format: "%.2f", silenceThreshold)
                let thresholdText = String(format: "%.4f", settings.vadThresholdRMS)
                let lastNonSilentText = stats.lastNonSilentAt?.description ?? "n/a"
                logger.log(.audio, "VAD silence timeout (rms=\(rmsText), peak=\(peakText), lastNonSilentAt=\(lastNonSilentText), silence=\(silenceText)s, threshold=\(thresholdText))")
                if case .recording = state, !isStopping {
                    stopRecordingFlow(reason: "VAD silence timeout (\(Int(silenceThreshold))s)")
                }
                return
            }
        }
        if state == .transcribing {
            let maxAllowed = settings.transcriptionTimeoutSeconds + 5
            if stateDuration() > maxAllowed {
                fail("Watchdog: transcription timeout")
            }
        }
        if state == .stopping {
            if stateDuration() > 5 {
                fail("Watchdog: stop timeout")
            }
        }
    }

    private func stateDuration() -> TimeInterval {
        if case .recording(let startedAt) = state {
            return Date().timeIntervalSince(startedAt)
        }
        return Date().timeIntervalSince(stateEnteredAt)
    }

    private func updateHUD(for state: DictationState) {
        guard settings.showHUD else {
            hudController.hide()
            return
        }
        switch state {
        case .recording:
            hudController.show(text: "Listening…", mode: .listening)
        case .stopping:
            hudController.show(text: "Stopping…", mode: .processing)
        case .transcribing:
            hudController.show(text: "Transcribing…", mode: .processing)
        case .inserting:
            hudController.show(text: "Inserting…", mode: .processing)
        case .armed:
            hudController.show(text: "Dicta Ready", mode: .neutral)
        case .idle:
            hudController.hide()
        case .error:
            hudController.show(text: "Error", mode: .error)
        }
    }

    func debugSummary() -> String {
        let permissionsSummary = "Mic: \(permissions.microphoneStatus().rawValue), Speech: \(permissions.speechStatus().rawValue), Accessibility: \(permissions.accessibilityStatus().rawValue)"
        let hotkeySummary = settings.hotkey.displayString
        let stateSummary = state.displayName
        let deviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown"
        let stats = lastRecordingInfo?.stats ?? audioRecorder.currentStats()
        let fileSize = lastRecordingInfo?.fileSizeBytes ?? 0
        let duration = lastRecordingInfo?.duration ?? 0
        let transcriptionDuration = lastTranscriptionDuration ?? 0
        let lastNonSilentAge = stats.lastNonSilentAt.map { Date().timeIntervalSince($0) }
        let phraseMapCount = PhraseMapStore.mergedMap(settings: settings).count
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return """
        Dicta Version: \(version) (\(build))
        State: \(stateSummary)
        Hotkey: \(hotkeySummary)
        Language Identifier: \(settings.languageIdentifier)
        Smart Punctuation: \(settings.smartPunctuationEnabled)
        Phrase Map Enabled: \(settings.phraseMapEnabled)
        Phrase Map Entries: \(phraseMapCount)
        Insertion Mode: \(settings.insertionMode.rawValue)
        Permissions: \(permissionsSummary)
        Audio Device: \(deviceName)
        Sample Rate: \(stats.sampleRate)
        Frames Received: \(stats.framesReceived)
        Bytes Written: \(stats.bytesWritten)
        Peak RMS: \(String(format: "%.4f", stats.peakRMS))
        Current RMS: \(String(format: "%.4f", stats.currentRMS))
        VAD Threshold RMS: \(String(format: "%.4f", settings.vadThresholdRMS))
        Silence Timeout: \(String(format: "%.2f", settings.silenceTimeoutSeconds))s
        Last Non-Silent At: \(stats.lastNonSilentAt?.description ?? "n/a")
        Last Non-Silent Age: \(lastNonSilentAge.map { String(format: "%.2f", $0) } ?? "n/a")s
        Last Frame At: \(stats.lastFrameAt?.description ?? "n/a")
        Recording Duration: \(String(format: "%.2f", duration))s
        Audio File Size: \(fileSize) bytes
        Transcription Duration: \(String(format: "%.2f", transcriptionDuration))s
        Transcript Length: \(lastTranscript.count)
        Last Transcription Error: \(lastTranscriptionErrorDetails)
        Last Insertion Result: \(lastInsertionResult) (mode: \(lastInsertionMode))
        Last Error: \(lastError.isEmpty ? "none" : lastError)
        """
    }

    private nonisolated static func detailedErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    private func withTimeout<T>(seconds: Double, timeoutError: Error, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
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
}
