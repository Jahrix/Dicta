import Foundation
import Combine
import AppKit
import AVFoundation

enum DictationTrigger: String {
    case pushToTalk
    case longDictation

    var displayName: String {
        switch self {
        case .pushToTalk: return "Push-to-Talk"
        case .longDictation: return "Long Dictation"
        }
    }
}

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
    private let localTranscriptionEngine: TranscriptionEngine
    private let insertionManager: InsertionManager
    private let hudController: PillHUDController

    private var sessionRecordingURL: URL?
    private var lastRecordingInfo: RecordingInfo?
    private var lastTranscriptionDuration: TimeInterval?
    private var lastTranscriptionErrorDetails: String = "none"
    private var lastInsertionMode: String = "none"
    private var lastInsertionResult: String = "none"
    private var finalRawText: String = ""
    private var finalProcessedText: String = ""
    private var transcriptionTask: Task<Void, Never>?
    private var insertionTask: Task<Void, Never>?
    private var maxRecordingTask: Task<Void, Never>?
    private var startRecordingTask: Task<Void, Never>?
    private var startRequestID: UUID?
    private let watchdogQueue = DispatchQueue(label: "com.dicta.watchdog", qos: .utility)
    private var watchdogTimer: DispatchSourceTimer?
    private var noFramesTask: Task<Void, Never>?
    private var stateEnteredAt = Date()
    private var isStopping = false
    private var activeTrigger: DictationTrigger?
    private var isPushToTalkHeld = false
    private var hudSmoothedLevel: Double = 0
    private var lastHUDRenderAt = Date.distantPast
    private var lastHUDMode: PillHUDMode?
    private var lastHUDQuantizedLevel = -1

    private var cancellables = Set<AnyCancellable>()

    var currentTrigger: DictationTrigger? {
        activeTrigger
    }

    init(settings: SettingsModel, permissions: PermissionsManager, logger: DiagnosticsLogger) {
        self.settings = settings
        self.permissions = permissions
        self.logger = logger
        self.audioRecorder = AudioRecorder(logger: logger)
        self.transcriptionEngine = AppleSpeechTranscriptionEngine(settings: settings, logger: logger)
        self.localTranscriptionEngine = LocalWhisperCppEngine(settings: settings, logger: logger)
        self.insertionManager = InsertionManager(
            pasteboardInserter: PasteboardInserter(logger: logger),
            accessibilityInserter: AccessibilityTyperInserter(logger: logger),
            logger: logger
        )
        self.hudController = PillHUDController(settings: settings)

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
                self?.renderHUD(force: true)
            }
            .store(in: &cancellables)

        Publishers.Merge3(settings.$selectedThemeID.map { _ in () },
                          settings.$customThemeEnabled.map { _ in () },
                          settings.$customThemeHex.map { _ in () })
            .sink { [weak self] _ in
                self?.renderHUD(force: true)
            }
            .store(in: &cancellables)

        startWatchdog()
    }

    func toggleDictation() {
        toggleLongDictation()
    }

    func beginRecording(trigger: DictationTrigger) {
        logger.log(.state, "Begin requested via \(trigger.displayName) in state \(state.displayName)")
        switch state {
        case .idle:
            activeTrigger = trigger
            if trigger == .pushToTalk {
                isPushToTalkHeld = true
            }
            startRecordingFlow()
        case .recording:
            logger.log(.state, "Begin ignored while already recording via \(activeTrigger?.displayName ?? "unknown")")
        case .armed:
            if trigger == .pushToTalk {
                isPushToTalkHeld = true
            }
        case .stopping, .transcribing, .inserting, .error:
            logger.log(.state, "Begin ignored in state \(state.displayName)")
        }
    }

    func endRecording(trigger: DictationTrigger) {
        logger.log(.state, "End requested via \(trigger.displayName) in state \(state.displayName)")
        if trigger == .pushToTalk {
            isPushToTalkHeld = false
        }
        guard activeTrigger == trigger else {
            logger.log(.state, "End ignored because active trigger is \(activeTrigger?.displayName ?? "none")")
            return
        }
        switch state {
        case .armed:
            cancelAndReset(reason: "\(trigger.displayName) released before recording started")
        case .recording:
            stopRecordingFlow(reason: trigger == .pushToTalk ? "Push-to-Talk released" : "\(trigger.displayName) stopped")
        case .idle, .stopping, .transcribing, .inserting, .error:
            break
        }
    }

    func toggleLongDictation() {
        logger.log(.state, "Long dictation toggle requested in state \(state.displayName)")
        switch state {
        case .idle:
            beginRecording(trigger: .longDictation)
        case .recording where activeTrigger == .longDictation:
            endRecording(trigger: .longDictation)
        case .armed where activeTrigger == .longDictation:
            cancelAndReset(reason: "Long Dictation cancelled while arming")
        case .recording:
            logger.log(.state, "Long Dictation ignored while \(activeTrigger?.displayName ?? "another trigger") is active")
        case .stopping, .transcribing, .inserting:
            logger.log(.state, "Long Dictation ignored while busy")
        case .error:
            transition(to: .idle, reason: "Reset after error")
            renderHUD(force: true)
        default:
            break
        }
    }

    func insert(text: String) async throws {
        let result = await insertionManager.insert(text: text,
                                                   mode: settings.insertionMode,
                                                   restoreClipboard: settings.restoreClipboard)
        if case .failed(let error) = result {
            throw error
        }
    }

    private func startRecordingFlow() {
        lastError = ""
        lastTranscriptionErrorDetails = "none"
        lastInsertionMode = "none"
        lastInsertionResult = "none"
        finalRawText = ""
        finalProcessedText = ""
        sessionRecordingURL = nil
        startRecordingTask?.cancel()
        let requestID = UUID()
        startRequestID = requestID
        transition(to: .armed, reason: "Starting dictation")
        renderHUD(force: true)
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
                self.sessionRecordingURL = url
                self.lastRecordingInfo = nil
                self.transition(to: .recording(startedAt: Date()), reason: "Recording started")
                self.startMaxRecordingTimer()
                self.startNoFramesCheck()
                self.renderHUD(force: true)
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
        if activeTrigger == .pushToTalk {
            isPushToTalkHeld = false
        }
        activeTrigger = nil
        renderHUD(force: true)
        NSSound.beep()

        let languageIdentifier = settings.languageIdentifier
        let preferOnDevice = settings.preferOnDevice
        let transcriptionTimeout = settings.transcriptionTimeoutSeconds > 0 ? settings.transcriptionTimeoutSeconds : 20.0

        transcriptionTask?.cancel()
        transcriptionTask = Task.detached { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isStopping = false
                }
            }
            do {
                let recordingInfo = try await self.audioRecorder.stopRecording()
                DiagnosticsManager.shared.addRecentAudio(recordingInfo.url)
                await MainActor.run {
                    self.logger.log(.audio, "Stop recording finished (file: \(recordingInfo.url.lastPathComponent), duration: \(String(format: "%.2f", recordingInfo.duration))s, bytes: \(recordingInfo.fileSizeBytes), frames: \(recordingInfo.stats.framesReceived))")
                }
                await MainActor.run {
                    self.sessionRecordingURL = recordingInfo.url
                    self.lastRecordingInfo = recordingInfo
                    self.transition(to: .transcribing, reason: "Recording stopped")
                    self.renderHUD(force: true)
                }
                if recordingInfo.stats.framesReceived == 0 || recordingInfo.fileSizeBytes == 0 {
                    await MainActor.run {
                        self.fail("Empty audio file (no frames captured)")
                    }
                    return
                }
                let durationText = String(format: "%.2f", recordingInfo.duration)
                await MainActor.run {
                    self.logger.log(.transcription, "Final transcribe start (full file=\(recordingInfo.url.lastPathComponent), duration=\(durationText)s)")
                }
                await self.performTranscription(url: recordingInfo.url,
                                                languageIdentifier: languageIdentifier,
                                                preferOnDevice: preferOnDevice,
                                                timeout: transcriptionTimeout,
                                                recordingDuration: recordingInfo.duration)
            } catch {
                await MainActor.run {
                    self.fail("Recording error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performTranscription(url: URL, languageIdentifier: String, preferOnDevice: Bool, timeout: Double, recordingDuration: TimeInterval) async {
        do {
            let locale = Locale(identifier: languageIdentifier)
            let start = Date()
            let rawText: String
            let prompt = settings.effectivePrompt()
            logger.log(.transcription, "Final transcription engine: local_whisper_cpp")
            do {
                rawText = try await withTimeout(seconds: timeout, timeoutError: TranscriptionError.timeout) {
                    try await self.localTranscriptionEngine.transcribeFile(url: url,
                                                                           locale: locale,
                                                                           prompt: prompt)
                }
                logger.log(.transcription, "LocalASR finish (length=\(rawText.count))")
            } catch {
                let details = Self.detailedErrorDescription(error)
                if shouldFallbackToAppleSpeech(for: error) {
                    logger.log(.transcription, "Fallback to AppleSpeech: \(details)")
                    logger.log(.transcription, "AppleSpeech start (file=\(url.lastPathComponent), locale=\(languageIdentifier), preferOnDevice=\(preferOnDevice))")
                    rawText = try await withTimeout(seconds: timeout, timeoutError: TranscriptionError.timeout) {
                        try await self.transcriptionEngine.transcribeFile(url: url,
                                                                         locale: locale,
                                                                         prompt: prompt)
                    }
                } else {
                    throw error
                }
            }
            let duration = Date().timeIntervalSince(start)
            await MainActor.run {
                self.lastTranscriptionDuration = duration
                self.lastTranscriptionErrorDetails = "none"
            }
            let durationText = String(format: "%.2f", recordingDuration)
            logger.log(.transcription, "Final transcribe finish (full file=\(url.lastPathComponent), duration=\(durationText)s)")
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

    private func shouldFallbackToAppleSpeech(for error: Error) -> Bool {
        if case TranscriptionError.timeout = error {
            return false
        }
        if case TranscriptionError.noSpeechDetected = error {
            return false
        }
        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("local asr unavailable")
            || description.contains("failed after retry")
            || description.contains("wav conversion failed")
    }

    private func handleTranscriptionSuccess(_ result: TranscriptionResult) {
        let rawText = result.text
        finalRawText = rawText
        logger.log(.transcription, "Transcript (raw): \(rawText)", verbose: true)
        let processedText = TextPostProcessor.process(rawText, settings: settings)
        finalProcessedText = processedText
        logger.log(.transcription, "Transcript (post): \(processedText)", verbose: true)

        guard !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastTranscriptionErrorDetails = "No speech detected"
            lastInsertionMode = settings.insertionMode.rawValue
            lastInsertionResult = "skipped: no speech detected"
            fail("No speech detected")
            return
        }

        logger.log(.transcription, "Final chosen for paste (chars: \(processedText.count))")
        lastTranscript = processedText
        transition(to: .inserting, reason: "Transcription complete")
        renderHUD(force: true)

        let insertionMode = settings.insertionMode
        let restoreClipboard = settings.restoreClipboard
        let insertionTimeout = settings.insertionTimeoutSeconds
        lastInsertionMode = insertionMode.rawValue
        lastInsertionResult = "pending"

        insertionTask?.cancel()
        insertionTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                await MainActor.run {
                    self.logger.log(.insertion, "Insertion started (mode: \(insertionMode.rawValue), chars: \(processedText.count))")
                }
                let result = try await self.withTimeout(seconds: insertionTimeout, timeoutError: InsertionError.timeout) {
                    await self.insertionManager.insert(text: processedText,
                                                       mode: insertionMode,
                                                       restoreClipboard: restoreClipboard)
                }
                switch result {
                case .failed(let error):
                    throw error
                case .pasted:
                    await MainActor.run {
                        self.lastInsertionResult = "pasted"
                        self.transition(to: .idle, reason: "Insertion complete")
                        self.renderHUD(force: true)
                    }
                case .attempted:
                    await MainActor.run {
                        self.lastInsertionResult = "attempted"
                        self.transition(to: .idle, reason: "Insertion complete (attempted)")
                        self.renderHUD(force: true)
                    }
                case .clipboardOnly:
                    await MainActor.run {
                        self.lastInsertionResult = "clipboard-only"
                        self.transition(to: .idle, reason: "Insertion complete (clipboard only)")
                        self.renderHUD(force: true)
                    }
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        self.logger.log(.insertion, "Insertion cancelled")
                    }
                    return
                }
                let details = Self.detailedErrorDescription(error)
                await MainActor.run {
                    let message = "Insertion failed: \(error.localizedDescription)"
                    self.lastInsertionResult = "failed: \(details)"
                    self.fail(message)
                    NotificationPresenter.shared.notify(title: "Dicta Insert Failed", body: message)
                }
                await MainActor.run {
                    self.logger.log(.insertion, "Insertion failed: \(details)")
                }
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
        activeTrigger = nil
        isPushToTalkHeld = false
        audioRecorder.cancelRecording()
        sessionRecordingURL = nil
        transition(to: .idle, reason: reason)
        renderHUD(force: true)
    }

    private func transition(to newState: DictationState, reason: String) {
        logger.log(.state, "State \(state.displayName) → \(newState.displayName) (\(reason))")
        state = newState
        stateEnteredAt = Date()
        if case .idle = newState {
            activeTrigger = nil
            isPushToTalkHeld = false
            hudSmoothedLevel = 0
        }
        if case .error = newState {
            activeTrigger = nil
            isPushToTalkHeld = false
        }
    }

    private func fail(_ message: String) {
        lastError = message
        transition(to: .error(message), reason: message)
        renderHUD(force: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if case .error = self.state {
                self.transition(to: .idle, reason: "Auto reset after error")
                self.renderHUD(force: true)
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
            renderHUD(force: false)
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

        if state == .transcribing || state == .stopping || state == .inserting {
            renderHUD(force: false)
        }

        if state == .transcribing {
            let maxAllowed = settings.transcriptionTimeoutSeconds + 5
            if stateDuration() > maxAllowed {
                fail("Watchdog: transcription timeout")
            }
        }

        if state == .stopping, stateDuration() > 5 {
            fail("Watchdog: stop timeout")
        }
    }

    private func stateDuration() -> TimeInterval {
        if case .recording(let startedAt) = state {
            return Date().timeIntervalSince(startedAt)
        }
        return Date().timeIntervalSince(stateEnteredAt)
    }

    private func renderHUD(force: Bool) {
        guard settings.showHUD else {
            hudController.hide()
            lastHUDMode = nil
            lastHUDQuantizedLevel = -1
            return
        }

        let mode: PillHUDMode
        switch state {
        case .idle:
            hudController.hide()
            lastHUDMode = nil
            lastHUDQuantizedLevel = -1
            return
        case .armed, .recording:
            mode = .listening
        case .stopping, .transcribing, .inserting:
            mode = .transcribing
        case .error:
            mode = .error
        }

        let targetLevel: Double
        switch state {
        case .recording:
            let stats = audioRecorder.currentStats()
            let normalized = min(max(stats.currentRMS / max(settings.vadThresholdRMS * 4.0, 0.05), 0.0), 1.0)
            hudSmoothedLevel = (hudSmoothedLevel * 0.8) + (normalized * 0.2)
            targetLevel = hudSmoothedLevel
        case .armed:
            hudSmoothedLevel = 0.18
            targetLevel = hudSmoothedLevel
        case .stopping, .transcribing, .inserting:
            hudSmoothedLevel = max(hudSmoothedLevel * 0.85, 0.2)
            targetLevel = max(hudSmoothedLevel, 0.2)
        case .error:
            hudSmoothedLevel = 0.1
            targetLevel = 0.1
        case .idle:
            targetLevel = 0
        }

        let quantized = Int((targetLevel * 12).rounded())
        let now = Date()
        if !force,
           now.timeIntervalSince(lastHUDRenderAt) < 0.1,
           lastHUDMode == mode,
           lastHUDQuantizedLevel == quantized {
            return
        }

        lastHUDRenderAt = now
        lastHUDMode = mode
        lastHUDQuantizedLevel = quantized
        hudController.show(mode: mode, waveformLevel: targetLevel, theme: settings.effectiveTheme)
    }

    func debugSummary() -> String {
        let permissionsSummary = "Mic: \(permissions.microphoneStatus().rawValue), Speech: \(permissions.speechStatus().rawValue), Accessibility: \(permissions.accessibilityStatus().rawValue)"
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
        State: \(state.displayName)
        Active Trigger: \(activeTrigger?.displayName ?? "none")
        Push-to-Talk: \(settings.pushToTalkKeybind.displayString)
        Long Dictation: \(settings.longDictationKeybind.displayString)
        Language Identifier: \(settings.languageIdentifier)
        Smart Punctuation: \(settings.smartPunctuationEnabled)
        Phrase Map Enabled: \(settings.phraseMapEnabled)
        Phrase Map Entries: \(phraseMapCount)
        Theme: \(settings.effectiveTheme.name)
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
