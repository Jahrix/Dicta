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
        setupHotkey()
        statusItemController = StatusItemController(viewModel: menuViewModel)

        if !settingsModel.hasCompletedOnboarding {
            openOnboardingWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupHotkey() {
        hotkeyManager.onHotkey = { [weak self] in
            Task { @MainActor in
                if let hotkey = self?.settingsModel.hotkey {
                    self?.diagnosticsLogger.log(.hotkey, "Hotkey pressed (keyCode: \(hotkey.keyCode), modifiers: \(hotkey.modifiers))")
                } else {
                    self?.diagnosticsLogger.log(.hotkey, "Hotkey pressed")
                }
                self?.dictationController.toggleDictation()
            }
        }

        settingsModel.$hotkey
            .sink { [weak self] hotkey in
                self?.hotkeyManager.register(hotkey: hotkey)
                self?.diagnosticsLogger.log(.hotkey, "Registered hotkey \(hotkey.displayString)")
            }
            .store(in: &cancellables)

        hotkeyManager.register(hotkey: settingsModel.hotkey)
    }

    private func openSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView(model: settingsModel,
                                    permissions: permissionsManager,
                                    logger: diagnosticsLogger)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable],
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

