import Foundation
import AppKit

final class PasteboardInserter: TextInserter {
    private let logger: DiagnosticsLogger

    init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    func insert(text: String, restoreClipboard: Bool) async throws {
        let pasteboard = NSPasteboard.general
        let previousItems = restoreClipboard ? pasteboard.pasteboardItems : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try await Task.sleep(nanoseconds: 80_000_000)
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw InsertionError.noFocusedApp
        }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            throw InsertionError.frontmostIsDicta
        }

        simulatePasteShortcut()
        logger.log(.insertion, "Pasteboard insertion triggered")

        if restoreClipboard {
            try await Task.sleep(nanoseconds: 150_000_000)
            pasteboard.clearContents()
            if let previousItems {
                pasteboard.writeObjects(previousItems)
            }
        }
    }

    private func simulatePasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyV: CGKeyCode = 9 // V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
