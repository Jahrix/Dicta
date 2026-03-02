import AppKit
import Carbon.HIToolbox
import Foundation

final class EventTapHotkeyEngine: HotkeyEngine {
    var onEvent: ((HotkeyEvent) -> Void)?
    let requiresInputMonitoring = true

    private var bindings: [ManagedBinding] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var standalonePressed: [Keybind: Bool] = [:]

    func start(bindings: [ManagedBinding]) throws {
        stop()
        self.bindings = bindings
        standalonePressed.removeAll()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { proxy, type, event, userInfo in
                                              guard let userInfo else {
                                                  return Unmanaged.passUnretained(event)
                                              }
                                              let engine = Unmanaged<EventTapHotkeyEngine>.fromOpaque(userInfo).takeUnretainedValue()
                                              return engine.handle(proxy: proxy, type: type, event: event)
                                          },
                                          userInfo: userInfo) else {
            throw HotkeyEngineError.inputMonitoringRequired
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        bindings.removeAll()
        standalonePressed.removeAll()
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            return handleKeyEvent(type: type, event: event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).hotkeyRelevant
        let phase: HotkeyPhase = type == .keyDown ? .down : .up

        for managed in bindings where managed.binding.kind == .combo {
            if managed.binding.matchesCombo(keyCode: keyCode, modifiers: flags) {
                onEvent?(HotkeyEvent(action: managed.action, phase: phase))
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        for managed in bindings where managed.binding.kind == .standaloneKey && managed.binding.keyCode == keyCode {
            let wasPressed = standalonePressed[managed.binding] ?? false
            let phase: HotkeyPhase = wasPressed ? .up : .down
            standalonePressed[managed.binding] = !wasPressed
            onEvent?(HotkeyEvent(action: managed.action, phase: phase))
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
