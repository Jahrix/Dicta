import Foundation
import ApplicationServices

final class AccessibilityTyperInserter: TextInserter {
    private let logger: DiagnosticsLogger

    init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    func insert(text: String, restoreClipboard: Bool, targetApp: FrontmostApp?) async throws {
        guard AXIsProcessTrusted() else {
            throw InsertionError.accessibilityDenied
        }

        let system = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard status == .success, let element = focusedElement else {
            throw InsertionError.focusedElementUnavailable
        }

        var currentValue: AnyObject?
        let valueStatus = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &currentValue)
        var rangeValue: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue)

        guard valueStatus == .success, rangeStatus == .success,
              let currentText = currentValue as? String,
              let rangeValue,
              let range = Self.extractRange(from: rangeValue) else {
            throw InsertionError.insertionFailed
        }

        let nsText = currentText as NSString
        let safeLocation = max(0, min(range.location, nsText.length))
        let safeLength = max(0, min(range.length, nsText.length - safeLocation))
        let newText = nsText.replacingCharacters(in: NSRange(location: safeLocation, length: safeLength), with: text)

        let setValueStatus = AXUIElementSetAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, newText as CFTypeRef)
        guard setValueStatus == .success else {
            throw InsertionError.insertionFailed
        }

        var newRange = CFRange(location: safeLocation + (text as NSString).length, length: 0)
        if let rangeAX = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, rangeAX)
        }
        logger.log(.insertion, "Accessibility insertion succeeded")
    }

    private static func extractRange(from value: AnyObject) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        if AXValueGetValue(axValue, .cfRange, &range) {
            return range
        }
        return nil
    }
}
