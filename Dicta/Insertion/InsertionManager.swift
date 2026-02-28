import Foundation
import ApplicationServices

protocol TextInserter {
    func insert(text: String, restoreClipboard: Bool) async throws
}

enum InsertionError: Error, LocalizedError {
    case accessibilityDenied
    case focusedElementUnavailable
    case insertionFailed
    case noFocusedApp
    case frontmostIsDicta
    case timeout

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: return "Accessibility permission not granted"
        case .focusedElementUnavailable: return "Focused element unavailable"
        case .insertionFailed: return "Insertion failed"
        case .noFocusedApp: return "No focused app available"
        case .frontmostIsDicta: return "Frontmost app is Dicta"
        case .timeout: return "Insertion timed out"
        }
    }
}

final class InsertionManager {
    private let pasteboardInserter: PasteboardInserter
    private let accessibilityInserter: AccessibilityTyperInserter
    private let logger: DiagnosticsLogger

    init(pasteboardInserter: PasteboardInserter, accessibilityInserter: AccessibilityTyperInserter, logger: DiagnosticsLogger) {
        self.pasteboardInserter = pasteboardInserter
        self.accessibilityInserter = accessibilityInserter
        self.logger = logger
    }

    func insert(text: String, mode: InsertionMode, restoreClipboard: Bool) async throws {
        switch mode {
        case .pasteboard:
            logger.log(.insertion, "Insertion mode: pasteboard")
            do {
                try await pasteboardInserter.insert(text: text, restoreClipboard: restoreClipboard)
            } catch {
                if let insertionError = error as? InsertionError,
                   (insertionError == .frontmostIsDicta || insertionError == .noFocusedApp) {
                    throw error
                }
                if AXIsProcessTrusted() {
                    logger.log(.insertion, "Pasteboard insert failed, attempting accessibility fallback: \(error.localizedDescription)")
                    try await accessibilityInserter.insert(text: text, restoreClipboard: restoreClipboard)
                } else {
                    throw error
                }
            }
        case .accessibility:
            do {
                logger.log(.insertion, "Insertion mode: accessibility")
                try await accessibilityInserter.insert(text: text, restoreClipboard: restoreClipboard)
            } catch {
                logger.log(.insertion, "Accessibility insert failed, falling back to pasteboard: \(error.localizedDescription)")
                try await pasteboardInserter.insert(text: text, restoreClipboard: restoreClipboard)
            }
        }
    }
}
