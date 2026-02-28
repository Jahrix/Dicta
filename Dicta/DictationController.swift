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
    private let insertionManager: InsertionManager
    private let hudController = HUDController()

    private var currentRecordingURL: URL?
    private var lastRecordingInfo: RecordingInfo?
    private var lastTranscriptionDuration: TimeInterval?
    private var transcriptionTask: Task<Void, Never>?
    private var insertionTask: Task<Void, Never>?
    private var maxRecordingTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var noFramesTask: Task<Void, Never>?
    private var stateEnteredAt = Date()

    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsModel, permissions: PermissionsManager, logger: DiagnosticsLogger) {
        self.settings = settings
        self.permissions = permissions
        self.logger = logger
        self.audioRecorder = AudioRecorder(logger: logger)
        self.transcriptionEngine = AppleSpeechTranscriptionEngine(logger: logger)
        self.insertionManager = InsertionManager(
            pasteboardInserter: PasteboardInserter(logger: logger),
            accessibilityInserter: AccessibilityTyperInserter(logger: logger),
            logger: logger
        )

        audioRecorder.onConfigurationChange = { [weak self] in
            Task { @MainActor in
                self?.fail("Audio device changed or interrupted")
            }
        }

        settings.$verboseLogging
            .sink { [weak self] enabled in
                self?.logger.verboseEnabled = enabled
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
        try await insertionManager.insert(text: text, mode: settings.insertionMode, restoreClipboard: settings.restoreClipboard)
    }

    private func startRecordingFlow() {
        transition(to: .armed, reason: "Starting dictation")
        updateHUD(for: .armed)
        NSSound.beep()

        Task.detached { [weak self] in
            guard let self else { return }
            await self.ensurePermissionsAndStartRecording()
        }
    }

    private func ensurePermissionsAndStartRecording() async {
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

        do {
            let url = try audioRecorder.startRecording()
            await MainActor.run {
                self.currentRecordingURL = url
                self.lastRecordingInfo = nil
                self.transition(to: .recording(startedAt: Date()), reason: "Recording started")
                self.startMaxRecordingTimer()
                self.startNoFramesCheck()
                self.updateHUD(for: self.state)
            }
        } catch {
            await MainActor.run {
                self.fail("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecordingFlow(reason: String) {
        maxRecordingTask?.cancel()
        noFramesTask?.cancel()
        transition(to: .stopping, reason: reason)
        updateHUD(for: .stopping)
        NSSound.beep()

        let languageIdentifier = settings.languageIdentifier
        let preferOnDevice = settings.preferOnDevice
        let transcriptionTimeout = settings.transcriptionTimeoutSeconds

        transcriptionTask?.cancel()
        transcriptionTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let recordingInfo = try await self.audioRecorder.stopRecording()
                DiagnosticsManager.shared.addRecentAudio(recordingInfo.url)
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
            logger.log(.transcription, "Transcription started for \(url.lastPathComponent)")
            let locale = Locale(identifier: languageIdentifier)
            let start = Date()
            let result = try await withTimeout(seconds: timeout, timeoutError: TranscriptionError.timeout) {
                try await self.transcriptionEngine.transcribe(url: url, locale: locale, preferOnDevice: preferOnDevice)
            }
            let duration = Date().timeIntervalSince(start)
            await MainActor.run {
                self.lastTranscriptionDuration = duration
            }
            logger.log(.transcription, "Transcription finished (length: \(result.text.count))")
            await MainActor.run {
                self.handleTranscriptionSuccess(result)
            }
        } catch {
            await MainActor.run {
                self.fail("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleTranscriptionSuccess(_ result: TranscriptionResult) {
        let cleanText = normalize(text: result.text)
        lastTranscript = cleanText
        transition(to: .inserting, reason: "Transcription complete")
        updateHUD(for: .inserting)

        let insertionMode = settings.insertionMode
        let restoreClipboard = settings.restoreClipboard
        let insertionTimeout = settings.insertionTimeoutSeconds

        insertionTask?.cancel()
        insertionTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.withTimeout(seconds: insertionTimeout, timeoutError: InsertionError.timeout) {
                    try await self.insertionManager.insert(text: cleanText, mode: insertionMode, restoreClipboard: restoreClipboard)
                }
                await MainActor.run {
                    self.transition(to: .idle, reason: "Insertion complete")
                    self.updateHUD(for: .idle)
                }
            } catch {
                await MainActor.run {
                    let message = "Insertion failed: \(error.localizedDescription)"
                    self.fail(message)
                    NotificationPresenter.shared.notify(title: "Dicta Insert Failed", body: message)
                }
            }
        }
    }

    private func cancelAndReset(reason: String) {
        logger.log(.state, "Cancel: \(reason)")
        transcriptionTask?.cancel()
        insertionTask?.cancel()
        maxRecordingTask?.cancel()
        noFramesTask?.cancel()
        audioRecorder.cancelRecording()
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
        watchdogTask?.cancel()
        watchdogTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.runWatchdogTick()
            }
        }
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
        if case .recording = state {
            let maxAllowed = settings.maxRecordingSeconds + 5
            if stateDuration() > maxAllowed {
                fail("Watchdog: recording timeout")
                return
            }
            let stats = audioRecorder.currentStats()
            if stats.framesReceived > 0, let lastFrameAt = stats.lastFrameAt {
                let silenceThreshold = settings.silenceTimeoutSeconds
                if Date().timeIntervalSince(lastFrameAt) > silenceThreshold {
                    stopRecordingFlow(reason: "Silence timeout (\(Int(silenceThreshold))s)")
                }
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

    private func normalize(text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.first {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(first).uppercased())
        }
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        return cleaned
    }

    private func updateHUD(for state: DictationState) {
        guard settings.showHUD else {
            hudController.hide()
            return
        }
        switch state {
        case .recording:
            hudController.show(text: "Recording…")
        case .stopping:
            hudController.show(text: "Stopping…")
        case .transcribing:
            hudController.show(text: "Transcribing…")
        case .inserting:
            hudController.show(text: "Inserting…")
        case .armed:
            hudController.show(text: "Dicta Ready")
        case .idle:
            hudController.hide()
        case .error:
            hudController.show(text: "Error")
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return """
        Dicta Version: \(version) (\(build))
        State: \(stateSummary)
        Hotkey: \(hotkeySummary)
        Permissions: \(permissionsSummary)
        Audio Device: \(deviceName)
        Sample Rate: \(stats.sampleRate)
        Frames Received: \(stats.framesReceived)
        Bytes Written: \(stats.bytesWritten)
        Peak RMS: \(String(format: "%.4f", stats.peakRMS))
        Last Frame At: \(stats.lastFrameAt?.description ?? "n/a")
        Recording Duration: \(String(format: "%.2f", duration))s
        Audio File Size: \(fileSize) bytes
        Transcription Duration: \(String(format: "%.2f", transcriptionDuration))s
        Transcript Length: \(lastTranscript.count)
        Last Error: \(lastError.isEmpty ? "none" : lastError)
        """
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
