import Foundation
import Carbon.HIToolbox

final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var currentHotkey: Hotkey?

    func register(hotkey: Hotkey) {
        unregister()
        currentHotkey = hotkey

        let hotKeyID = EventHotKeyID(signature: OSType(0x44544341), id: 1) // 'DTCA'
        let target = GetEventDispatcherTarget()

        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID, target, 0, &hotkeyRef)
        if status != noErr {
            return
        }

        if handler == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(target, { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotkey?()
                return noErr
            }, 1, &eventSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &handler)
        }
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }
}
