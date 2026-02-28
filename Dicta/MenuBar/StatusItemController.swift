import AppKit
import Combine

@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()

    private let toggleItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
    private let lastTranscriptItem = NSMenuItem(title: "Last Transcript", action: nil, keyEquivalent: "")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let pasteLastTranscriptItem = NSMenuItem(title: "Paste Again", action: #selector(pasteLastTranscript), keyEquivalent: "")

    private let diagnosticsItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
    private let exportLogsItem = NSMenuItem(title: "Export Debug Bundle", action: #selector(exportLogs), keyEquivalent: "")
    private let showLastErrorItem = NSMenuItem(title: "Show Last Error", action: #selector(showLastError), keyEquivalent: "")
    private let copyLastErrorItem = NSMenuItem(title: "Copy Last Error", action: #selector(copyLastError), keyEquivalent: "")
    private let copyDebugSummaryItem = NSMenuItem(title: "Copy Debug Summary", action: #selector(copyDebugSummary), keyEquivalent: "")
    private let permissionsItem = NSMenuItem(title: "Permissions Status", action: #selector(showPermissions), keyEquivalent: "")

    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit Dicta", action: #selector(quitApp), keyEquivalent: "q")

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        setupMenu()
        bindViewModel()
    }

    private func setupMenu() {
        statusItem.menu = menu
        statusItem.button?.image = icon(for: .idle)
        statusItem.button?.image?.isTemplate = true

        toggleItem.target = self
        copyLastTranscriptItem.target = self
        pasteLastTranscriptItem.target = self
        exportLogsItem.target = self
        showLastErrorItem.target = self
        copyLastErrorItem.target = self
        copyDebugSummaryItem.target = self
        permissionsItem.target = self
        settingsItem.target = self
        quitItem.target = self

        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let lastTranscriptMenu = NSMenu()
        lastTranscriptMenu.addItem(copyLastTranscriptItem)
        lastTranscriptMenu.addItem(pasteLastTranscriptItem)
        lastTranscriptItem.submenu = lastTranscriptMenu
        menu.addItem(lastTranscriptItem)

        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.addItem(copyDebugSummaryItem)
        diagnosticsMenu.addItem(copyLastErrorItem)
        diagnosticsMenu.addItem(exportLogsItem)
        diagnosticsMenu.addItem(showLastErrorItem)
        diagnosticsMenu.addItem(permissionsItem)
        diagnosticsItem.submenu = diagnosticsMenu
        menu.addItem(diagnosticsItem)

        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    private func bindViewModel() {
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.toggleItem.title = self?.viewModel.toggleTitle ?? "Start Dictation"
                self?.statusItem.button?.image = self?.icon(for: state)
            }
            .store(in: &cancellables)

        viewModel.$lastTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                let enabled = !text.isEmpty
                self?.copyLastTranscriptItem.isEnabled = enabled
                self?.pasteLastTranscriptItem.isEnabled = enabled
            }
            .store(in: &cancellables)

        viewModel.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.showLastErrorItem.isEnabled = !text.isEmpty
                self?.copyLastErrorItem.isEnabled = !text.isEmpty
            }
            .store(in: &cancellables)
    }

    private func icon(for state: DictationState) -> NSImage? {
        let symbolName: String
        switch state {
        case .idle, .armed:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .stopping:
            symbolName = "stop.circle"
        case .transcribing:
            symbolName = "waveform"
        case .inserting:
            symbolName = "arrow.down.doc"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleDictation() {
        viewModel.toggleDictation()
    }

    @objc private func copyLastTranscript() {
        viewModel.copyLastTranscript()
    }

    @objc private func pasteLastTranscript() {
        viewModel.pasteLastTranscript()
    }

    @objc private func exportLogs() {
        Task {
            await DiagnosticsManager.shared.exportDebugBundle()
        }
    }

    @objc private func showLastError() {
        guard !viewModel.lastError.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Last Error"
        alert.informativeText = viewModel.lastError
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func copyLastError() {
        viewModel.copyLastError()
    }

    @objc private func copyDebugSummary() {
        viewModel.copyDebugSummary()
    }

    @objc private func showPermissions() {
        viewModel.showPermissions()
    }

    @objc private func showSettings() {
        viewModel.showSettings()
    }

    @objc private func quitApp() {
        viewModel.quit()
    }
}
