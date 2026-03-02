import Foundation
import Combine
import AppKit

@MainActor
final class MenuViewModel: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastError: String = ""

    private let controller: DictationController
    private let settings: SettingsModel
    private let permissions: PermissionsManager
    private let logger: DiagnosticsLogger
    private var cancellables = Set<AnyCancellable>()

    private let showSettingsAction: () -> Void
    private let showDiagnosticsAction: () -> Void
    private let showPermissionsAction: () -> Void
    private let quitAction: () -> Void

    init(controller: DictationController,
         settings: SettingsModel,
         permissions: PermissionsManager,
         logger: DiagnosticsLogger,
         showSettings: @escaping () -> Void,
         showDiagnostics: @escaping () -> Void,
         showPermissions: @escaping () -> Void,
         quit: @escaping () -> Void) {
        self.controller = controller
        self.settings = settings
        self.permissions = permissions
        self.logger = logger
        self.showSettingsAction = showSettings
        self.showDiagnosticsAction = showDiagnostics
        self.showPermissionsAction = showPermissions
        self.quitAction = quit

        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
            .store(in: &cancellables)

        controller.$lastTranscript
            .receive(on: RunLoop.main)
            .assign(to: &$lastTranscript)

        controller.$lastError
            .receive(on: RunLoop.main)
            .assign(to: &$lastError)
    }

    var longDictationToggleTitle: String {
        switch state {
        case .recording where controller.currentTrigger == .longDictation:
            return "Stop Long Dictation"
        case .armed where controller.currentTrigger == .longDictation:
            return "Stop Long Dictation"
        default:
            return "Start Long Dictation"
        }
    }

    var pushToTalkLabel: String {
        "Push-to-Talk: \(settings.pushToTalkKeybind.displayString)"
    }

    var longDictationLabel: String {
        "Long Dictation: \(settings.longDictationKeybind.displayString)"
    }

    var statusLine: String {
        state.displayName
    }

    func permissionStatus(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone:
            return permissions.microphoneStatus()
        case .speech:
            return permissions.speechStatus()
        case .accessibility:
            return permissions.accessibilityStatus()
        }
    }

    func permissionStatusLabel(for kind: PermissionKind) -> String {
        let statusText: String
        switch permissionStatus(for: kind) {
        case .granted: statusText = "Granted"
        case .denied: statusText = "Not granted"
        case .notDetermined: statusText = "Not requested"
        }
        return "\(kind.displayName): \(statusText)"
    }

    func toggleLongDictation() {
        controller.toggleLongDictation()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastTranscript, forType: .string)
    }

    func copyLastError() {
        guard !lastError.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastError, forType: .string)
    }

    func copyDebugSummary() {
        let summary = controller.debugSummary()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary, forType: .string)
    }

    func pasteLastTranscript() {
        Task {
            guard !lastTranscript.isEmpty else { return }
            try? await controller.insert(text: lastTranscript)
        }
    }

    func showSettings() { showSettingsAction() }
    func showDiagnostics() { showDiagnosticsAction() }
    func showPermissions() { showPermissionsAction() }
    func quit() { quitAction() }
    func openSystemSettings(for kind: PermissionKind) { permissions.openSystemSettings(for: kind) }
}
