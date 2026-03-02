import Carbon.HIToolbox
import Foundation

final class CarbonHotkeyEngine: HotkeyEngine {
    var onEvent: ((HotkeyEvent) -> Void)?
    let requiresInputMonitoring = false

    private var handler: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionsByIdentifier: [UInt32: HotkeyAction] = [:]

    func start(bindings: [ManagedBinding]) throws {
        stop()
        actionsByIdentifier.removeAll()

        let comboBindings = bindings.filter { $0.binding.supportsCarbonHotkey }
        guard !comboBindings.isEmpty else { return }

        let target = GetEventDispatcherTarget()
        if handler == nil {
            var specs = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let status = InstallEventHandler(target, { _, event, userData in
                guard let event, let userData else { return noErr }
                let engine = Unmanaged<CarbonHotkeyEngine>.fromOpaque(userData).takeUnretainedValue()
                return engine.handle(event: event)
            }, specs.count, &specs, userData, &handler)
            guard status == noErr else {
                throw HotkeyEngineError.registrationFailed("Failed to install Carbon hotkey handler (\(status)).")
            }
        }

        for (index, managed) in comboBindings.enumerated() {
            let identifier = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: OSType(0x44494354), id: identifier)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(managed.binding.keyCode),
                                             managed.binding.modifiers.carbonHotkeyModifiers,
                                             hotKeyID,
                                             target,
                                             0,
                                             &hotKeyRef)
            guard status == noErr, let hotKeyRef else {
                stop()
                throw HotkeyEngineError.registrationFailed("Failed to register Carbon hotkey (\(status)).")
            }
            hotkeyRefs[identifier] = hotKeyRef
            actionsByIdentifier[identifier] = managed.action
        }
    }

    func stop() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        actionsByIdentifier.removeAll()
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        guard status == noErr, let action = actionsByIdentifier[hotKeyID.id] else { return noErr }
        let kind = GetEventKind(event)
        let phase: HotkeyPhase = kind == UInt32(kEventHotKeyReleased) ? .up : .down
        onEvent?(HotkeyEvent(action: action, phase: phase))
        return noErr
    }
}
