import Foundation
import AppKit
import Carbon.HIToolbox

struct Hotkey: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
        let modifierString = modifierSymbols
        let keyString = KeyCodeTranslator.shared.string(for: keyCode)
        return modifierString + keyString
    }

    private var modifierSymbols: String {
        var symbols = ""
        let flags = ModifierFlags(carbonFlags: modifiers)
        if flags.contains(.command) { symbols += "⌘" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.control) { symbols += "⌃" }
        return symbols
    }
}

struct ModifierFlags: OptionSet {
    let rawValue: UInt32
    static let command = ModifierFlags(rawValue: UInt32(cmdKey))
    static let option = ModifierFlags(rawValue: UInt32(optionKey))
    static let shift = ModifierFlags(rawValue: UInt32(shiftKey))
    static let control = ModifierFlags(rawValue: UInt32(controlKey))

    init(rawValue: UInt32) { self.rawValue = rawValue }

    init(carbonFlags: UInt32) {
        self.rawValue = carbonFlags
    }

    static func from(eventFlags: NSEvent.ModifierFlags) -> ModifierFlags {
        var flags: ModifierFlags = []
        if eventFlags.contains(.command) { flags.insert(.command) }
        if eventFlags.contains(.option) { flags.insert(.option) }
        if eventFlags.contains(.shift) { flags.insert(.shift) }
        if eventFlags.contains(.control) { flags.insert(.control) }
        return flags
    }
}

final class KeyCodeTranslator {
    static let shared = KeyCodeTranslator()

    private init() {}

    func string(for keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let c = keyCodeToCharacter(keyCode) {
            return c.uppercased()
        }
        return "#\(keyCode)"
    }

    private func keyCodeToCharacter(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(data, to: CFData.self)
        guard let layoutPtr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = UnsafeRawPointer(layoutPtr).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var length: Int = 0
        var chars: UniChar = 0

        let result = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            0,
            &deadKeyState,
            1,
            &length,
            &chars
        )
        if result != noErr { return nil }
        guard let scalar = UnicodeScalar(UInt32(chars)) else { return nil }
        return String(scalar)
    }

    private let specialKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Help): "?",
        UInt32(kVK_F18): "F18"
    ]
}
