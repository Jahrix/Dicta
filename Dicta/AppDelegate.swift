import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private let settingsModel = SettingsModel()
    private let diagnosticsLogger = DiagnosticsLogger.shared
    private let permissionsManager = PermissionsManager()

    private lazy var dictationController: DictationController = {
        DictationController(settings: settingsModel,
                            permissions: permissionsManager,
                            logger: diagnosticsLogger)
    }()

    private lazy var menuViewModel: MenuViewModel = {
        MenuViewModel(controller: dictationController,
                      settings: settingsModel,
                      permissions: permissionsManager,
                      logger: diagnosticsLogger,
                      showSettings: { [weak self] in self?.openSettingsWindow() },
                      showDiagnostics: { [weak self] in self?.openDiagnosticsWindow() },
                      showPermissions: { [weak self] in self?.openDiagnosticsWindow(selectPermissions: true) },
                      quit: { NSApp.terminate(nil) })
    }()

    private let hotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupHotkeys()
        statusItemController = StatusItemController(viewModel: menuViewModel)

        if !settingsModel.hasCompletedOnboarding {
            openOnboardingWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupHotkeys() {
        hotkeyManager.onBeginPushToTalk = { [weak self] in
            guard let self else { return }
            self.diagnosticsLogger.log(.hotkey, "PTT down (\(self.settingsModel.pushToTalkKeybind.displayString))")
            self.dictationController.beginRecording(trigger: .pushToTalk)
        }
        hotkeyManager.onEndPushToTalk = { [weak self] in
            guard let self else { return }
            self.diagnosticsLogger.log(.hotkey, "PTT up (\(self.settingsModel.pushToTalkKeybind.displayString))")
            self.dictationController.endRecording(trigger: .pushToTalk)
        }
        hotkeyManager.onToggleLongDictation = { [weak self] in
            guard let self else { return }
            self.diagnosticsLogger.log(.hotkey, "Long dictation toggle (\(self.settingsModel.longDictationKeybind.displayString))")
            self.dictationController.toggleLongDictation()
        }
        hotkeyManager.onInputMonitoringRequired = { [weak self] in
            self?.showInputMonitoringHintIfNeeded()
        }

        Publishers.CombineLatest(settingsModel.$pushToTalkKeybind, settingsModel.$longDictationKeybind)
            .sink { [weak self] ptt, long in
                guard let self else { return }
                self.hotkeyManager.register(ptt: ptt, long: long)
                self.diagnosticsLogger.log(.hotkey, "Registered keybinds: \(self.hotkeyManager.currentConfigurationSummary)")
            }
            .store(in: &cancellables)

        hotkeyManager.register(ptt: settingsModel.pushToTalkKeybind, long: settingsModel.longDictationKeybind)
    }

    private func showInputMonitoringHintIfNeeded() {
        guard !settingsModel.hasShownInputMonitoringHint else { return }
        settingsModel.hasShownInputMonitoringHint = true
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Required"
        alert.informativeText = "Push-to-Talk and standalone modifier keybinds need Input Monitoring on macOS. Long Dictation combo fallback will keep working where possible."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView(model: settingsModel,
                                    permissions: permissionsManager,
                                    logger: diagnosticsLogger)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Dicta Settings"
            window.center()
            window.contentView = NSHostingView(rootView: view)
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDiagnosticsWindow(selectPermissions: Bool = false) {
        if diagnosticsWindow == nil {
            let view = DiagnosticsView(model: settingsModel,
                                       permissions: permissionsManager,
                                       logger: diagnosticsLogger,
                                       selectPermissions: selectPermissions)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Dicta Diagnostics"
            window.center()
            window.contentView = NSHostingView(rootView: view)
            diagnosticsWindow = window
        }
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openOnboardingWindow() {
        let view = OnboardingView(model: settingsModel,
                                  permissions: permissionsManager,
                                  logger: diagnosticsLogger) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Welcome to Dicta"
        window.center()
        window.contentView = NSHostingView(rootView: view)
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
