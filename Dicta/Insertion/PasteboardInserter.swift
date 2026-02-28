import Foundation
import AppKit
import ApplicationServices

final class PasteboardInserter: TextInserter {
    private let logger: DiagnosticsLogger
    private static var didNotifyAccessibilityMissing = false

    init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(text, forType: .string)
    }

    func insert(text: String, restoreClipboard: Bool) async throws {
        let pasteboard = NSPasteboard.general
        let previousItems = restoreClipboard ? snapshotPasteboardItems(from: pasteboard) : nil

        logger.log(.insertion, "Pasteboard insertion starting (chars: \(text.count), restoreClipboard: \(restoreClipboard))")
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw InsertionError.insertionFailed
        }

        if let captured = NSWorkspace.shared.frontmostApplication {
            logger.log(.insertion, "Captured frontmost app: \(captured.bundleIdentifier ?? "unknown") pid=\(captured.processIdentifier)")
            if captured.bundleIdentifier == Bundle.main.bundleIdentifier {
                logger.log(.insertion, "Frontmost app is Dicta at capture time")
            } else {
                let activated = captured.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)
                logger.log(.insertion, "Re-activate frontmost app: \(activated ? "success" : "failed")")
            }
        } else {
            logger.log(.insertion, "No frontmost app captured")
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NotificationPresenter.shared.notify(title: "Dicta Insert Failed", body: "No focused app to paste into.")
            throw InsertionError.noFocusedApp
        }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            NotificationPresenter.shared.notify(title: "Dicta Insert Failed", body: "Dicta is frontmost; cannot paste.")
            throw InsertionError.frontmostIsDicta
        }

        let axTrusted = AXIsProcessTrusted()
        logger.log(.insertion, "AX trust: \(axTrusted ? "granted" : "not granted")")
        guard axTrusted else {
            logger.log(.insertion, "Auto-paste unavailable: Accessibility not granted (clipboard-only)")
            notifyAccessibilityMissingOnce()
            throw InsertionError.clipboardOnly
        }

        guard simulatePasteShortcut() else {
            throw InsertionError.insertionFailed
        }
        logger.log(.insertion, "Pasteboard insertion triggered for \(frontmost.bundleIdentifier ?? "unknown")")

        if restoreClipboard {
            try await Task.sleep(nanoseconds: 400_000_000)
            restorePasteboardItems(previousItems, to: pasteboard)
            logger.log(.insertion, "Clipboard restored after pasteboard insertion")
        }
    }

    private func simulatePasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let keyV: CGKeyCode = 9 // V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        guard let keyDown, let keyUp else { return false }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func notifyAccessibilityMissingOnce() {
        guard !Self.didNotifyAccessibilityMissing else { return }
        Self.didNotifyAccessibilityMissing = true
        NotificationPresenter.shared.notify(title: "Dicta", body: "Enable Accessibility to paste automatically.")
    }

    private func snapshotPasteboardItems(from pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        }
    }

    private func restorePasteboardItems(_ snapshots: [[NSPasteboard.PasteboardType: Data]]?, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard let snapshots, !snapshots.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshots.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot {
                item.setData(data, forType: type)
            }
            return item
        }
        _ = pasteboard.writeObjects(items)
    }
}
