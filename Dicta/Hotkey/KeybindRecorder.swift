import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class KeybindRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var helperText = ""

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var onRecord: ((Keybind) -> Void)?

    func start(onRecord: @escaping (Keybind) -> Void) {
        stop()
        self.onRecord = onRecord
        helperText = "Press a key or modifier"
        isRecording = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.hotkeyRelevant
            let keyCode = UInt16(event.keyCode)
            let keyName = KeyCodeTranslator.shared.string(for: UInt32(keyCode))
            let isFunctionKey = keyName.hasPrefix("F")
            guard !modifiers.isEmpty || isFunctionKey else {
                return nil
            }
            self.finish(with: Keybind(keyCode: keyCode, modifiers: modifiers, kind: .combo, side: nil))
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let standalone = Self.standaloneKeybind(from: event) else {
                return event
            }
            self.finish(with: standalone)
            return nil
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        onRecord = nil
        helperText = ""
        isRecording = false
    }

    private func finish(with keybind: Keybind) {
        let onRecord = self.onRecord
        stop()
        onRecord?(keybind)
    }

    private static func standaloneKeybind(from event: NSEvent) -> Keybind? {
        let keyCode = UInt16(event.keyCode)
        switch keyCode {
        case UInt16(kVK_Shift):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .left)
        case UInt16(kVK_RightShift):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .right)
        case UInt16(kVK_Option):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .left)
        case UInt16(kVK_RightOption):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .right)
        case UInt16(kVK_Control):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .left)
        case UInt16(kVK_RightControl):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .right)
        case UInt16(kVK_Command):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .left)
        case UInt16(kVK_RightCommand):
            return Keybind(keyCode: keyCode, kind: .standaloneKey, side: .right)
        default:
            return nil
        }
    }
}
