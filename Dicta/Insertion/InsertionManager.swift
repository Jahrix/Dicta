import Foundation
import ApplicationServices

protocol TextInserter {
    func insert(text: String, restoreClipboard: Bool) async throws
}

enum InsertResult {
    case pasted
    case attempted
    case clipboardOnly
    case failed(Error)
}

enum InsertionError: Error, LocalizedError {
    case accessibilityDenied
    case focusedElementUnavailable
    case insertionFailed
    case noFocusedApp
    case frontmostIsDicta
    case clipboardOnly
    case timeout

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: return "Accessibility permission not granted"
        case .focusedElementUnavailable: return "Focused element unavailable"
        case .insertionFailed: return "Insertion failed"
        case .noFocusedApp: return "No focused app available"
        case .frontmostIsDicta: return "Frontmost app is Dicta"
        case .clipboardOnly: return "Auto-paste unavailable (clipboard only)"
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

    func insert(text: String, mode: InsertionMode, restoreClipboard: Bool, targetApp: FrontmostApp? = nil) async -> InsertResult {
        switch mode {
        case .pasteboard:
            logger.log(.insertion, "Insertion mode: pasteboard")
            do {
                try await pasteboardInserter.insert(text: text, restoreClipboard: restoreClipboard)
                logger.log(.insertion, "Insertion result: attempted")
                return .attempted
            } catch {
                if let insertionError = error as? InsertionError, insertionError == .clipboardOnly {
                    logger.log(.insertion, "Insertion result: clipboardOnly")
                    return .clipboardOnly
                }
                if AXIsProcessTrusted() {
                    logger.log(.insertion, "Pasteboard insert failed, attempting accessibility fallback: \(error.localizedDescription)")
                    do {
                        try await accessibilityInserter.insert(text: text, restoreClipboard: restoreClipboard)
                        logger.log(.insertion, "Insertion result: pasted")
                        return .pasted
                    } catch {
                        logger.log(.insertion, "Insertion failed: \(error.localizedDescription)")
                        return .failed(error)
                    }
                }
                logger.log(.insertion, "Insertion failed: \(error.localizedDescription)")
                return .failed(error)
            }
        case .accessibility:
            pasteboardInserter.copyToClipboard(text: text)
            do {
                logger.log(.insertion, "Insertion mode: accessibility")
                try await accessibilityInserter.insert(text: text, restoreClipboard: restoreClipboard)
                logger.log(.insertion, "Insertion result: pasted")
                return .pasted
            } catch {
                logger.log(.insertion, "Accessibility insert failed, falling back to pasteboard: \(error.localizedDescription)")
                do {
                    try await pasteboardInserter.insert(text: text, restoreClipboard: restoreClipboard)
                    logger.log(.insertion, "Insertion result: attempted")
                    return .attempted
                } catch {
                    if let insertionError = error as? InsertionError, insertionError == .clipboardOnly {
                        logger.log(.insertion, "Insertion result: clipboardOnly")
                        return .clipboardOnly
                    }
                    logger.log(.insertion, "Insertion failed: \(error.localizedDescription)")
                    return .failed(error)
                }
            }
        }
    }
}
