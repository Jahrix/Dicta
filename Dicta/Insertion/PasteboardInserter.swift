import Foundation
import AppKit
import ApplicationServices

final class PasteboardInserter: TextInserter {
    private let logger: DiagnosticsLogger

    init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    func insert(text: String, restoreClipboard: Bool) async throws {
        let pasteboard = NSPasteboard.general
        let previousItems = restoreClipboard ? snapshotPasteboardItems(from: pasteboard) : nil

        logger.log(.insertion, "Pasteboard insertion starting (chars: \(text.count), restoreClipboard: \(restoreClipboard))")
        do {
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw InsertionError.insertionFailed
            }

            try await Task.sleep(nanoseconds: 80_000_000)
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw InsertionError.noFocusedApp
            }
            if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
                throw InsertionError.frontmostIsDicta
            }

            guard simulatePasteShortcut() else {
                throw InsertionError.insertionFailed
            }
            logger.log(.insertion, "Pasteboard insertion triggered for \(frontmost.bundleIdentifier ?? "unknown")")

            if restoreClipboard {
                try await Task.sleep(nanoseconds: 150_000_000)
                restorePasteboardItems(previousItems, to: pasteboard)
                logger.log(.insertion, "Clipboard restored after pasteboard insertion")
            }
        } catch {
            if restoreClipboard {
                try? await Task.sleep(nanoseconds: 50_000_000)
                restorePasteboardItems(previousItems, to: pasteboard)
                logger.log(.insertion, "Clipboard restored after insertion failure")
            }
            throw error
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
