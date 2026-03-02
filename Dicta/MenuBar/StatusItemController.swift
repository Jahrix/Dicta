import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let viewModel: MenuViewModel
    private var cancellables = Set<AnyCancellable>()

    private let statusLineItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private let longToggleItem = NSMenuItem(title: "Start Long Dictation", action: #selector(toggleLongDictation), keyEquivalent: "")
    private let pushToTalkInfoItem = NSMenuItem(title: "Push-to-Talk", action: nil, keyEquivalent: "")
    private let longDictationInfoItem = NSMenuItem(title: "Long Dictation", action: nil, keyEquivalent: "")
    private let lastTranscriptItem = NSMenuItem(title: "Last Transcript", action: nil, keyEquivalent: "")
    private let copyLastTranscriptItem = NSMenuItem(title: "Copy", action: #selector(copyLastTranscript), keyEquivalent: "")
    private let pasteLastTranscriptItem = NSMenuItem(title: "Paste Again", action: #selector(pasteLastTranscript), keyEquivalent: "")

    private let diagnosticsItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
    private let openDiagnosticsItem = NSMenuItem(title: "Open Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
    private let exportLogsItem = NSMenuItem(title: "Export Logs…", action: #selector(exportLogs), keyEquivalent: "")
    private let showLastErrorItem = NSMenuItem(title: "Show Last Error", action: #selector(showLastError), keyEquivalent: "")
    private let copyLastErrorItem = NSMenuItem(title: "Copy Last Error", action: #selector(copyLastError), keyEquivalent: "")
    private let copyDebugSummaryItem = NSMenuItem(title: "Copy Debug Summary", action: #selector(copyDebugSummary), keyEquivalent: "")

    private let settingsItem = NSMenuItem(title: "Open Settings…", action: #selector(showSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit Dicta", action: #selector(quitApp), keyEquivalent: "q")

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        super.init()
        setupMenu()
        bindViewModel()
    }

    private func setupMenu() {
        statusItem.menu = menu
        menu.delegate = self
        statusItem.button?.image = icon(for: .idle)
        statusItem.button?.image?.isTemplate = true

        [longToggleItem, copyLastTranscriptItem, pasteLastTranscriptItem, openDiagnosticsItem,
         exportLogsItem, showLastErrorItem, copyLastErrorItem, copyDebugSummaryItem, settingsItem, quitItem]
            .forEach { $0.target = self }

        statusLineItem.isEnabled = false
        pushToTalkInfoItem.isEnabled = false
        longDictationInfoItem.isEnabled = false
        lastTranscriptItem.isEnabled = false
        copyLastTranscriptItem.isEnabled = false
        pasteLastTranscriptItem.isEnabled = false
        showLastErrorItem.isEnabled = false
        copyLastErrorItem.isEnabled = false

        menu.addItem(longToggleItem)
        menu.addItem(statusLineItem)
        menu.addItem(pushToTalkInfoItem)
        menu.addItem(longDictationInfoItem)
        menu.addItem(NSMenuItem.separator())

        let lastTranscriptMenu = NSMenu()
        lastTranscriptMenu.addItem(copyLastTranscriptItem)
        lastTranscriptMenu.addItem(pasteLastTranscriptItem)
        lastTranscriptItem.submenu = lastTranscriptMenu
        menu.addItem(lastTranscriptItem)

        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.addItem(openDiagnosticsItem)
        diagnosticsMenu.addItem(copyDebugSummaryItem)
        diagnosticsMenu.addItem(copyLastErrorItem)
        diagnosticsMenu.addItem(exportLogsItem)
        diagnosticsMenu.addItem(showLastErrorItem)
        diagnosticsItem.submenu = diagnosticsMenu
        menu.addItem(diagnosticsItem)

        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        pushToTalkInfoItem.title = viewModel.pushToTalkLabel
        longDictationInfoItem.title = viewModel.longDictationLabel
    }

    private func bindViewModel() {
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.longToggleItem.title = self.viewModel.longDictationToggleTitle
                self.statusLineItem.title = "Status: \(self.viewModel.statusLine)"
                self.pushToTalkInfoItem.title = self.viewModel.pushToTalkLabel
                self.longDictationInfoItem.title = self.viewModel.longDictationLabel
                self.statusItem.button?.image = self.icon(for: state)
                self.statusItem.button?.toolTip = "Dicta — \(self.viewModel.statusLine)"
            }
            .store(in: &cancellables)

        viewModel.$lastTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                let enabled = !text.isEmpty
                self?.copyLastTranscriptItem.isEnabled = enabled
                self?.pasteLastTranscriptItem.isEnabled = enabled
                self?.lastTranscriptItem.isEnabled = enabled
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

    func menuWillOpen(_ menu: NSMenu) {
        statusLineItem.title = "Status: \(viewModel.statusLine)"
        pushToTalkInfoItem.title = viewModel.pushToTalkLabel
        longDictationInfoItem.title = viewModel.longDictationLabel
    }

    private func icon(for state: DictationState) -> NSImage? {
        let symbolName: String
        switch state {
        case .idle, .armed:
            symbolName = "mic.circle"
        case .recording:
            symbolName = "mic.circle.fill"
        case .stopping:
            symbolName = "stop.circle.fill"
        case .transcribing:
            symbolName = "waveform.circle"
        case .inserting:
            symbolName = "arrow.down.doc"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleLongDictation() {
        viewModel.toggleLongDictation()
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

    @objc private func showDiagnostics() {
        viewModel.showDiagnostics()
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

    @objc private func showSettings() {
        viewModel.showSettings()
    }

    @objc private func quitApp() {
        viewModel.quit()
    }
}
