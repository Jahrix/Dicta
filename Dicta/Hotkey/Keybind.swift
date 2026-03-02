import AppKit
import Carbon.HIToolbox
import Foundation

enum KeybindKind: String, Codable {
    case combo
    case standaloneKey
}

enum ModifierSide: String, Codable {
    case left
    case right
}

enum HotkeyAction: String, Codable {
    case pushToTalk
    case longDictation
}

enum HotkeyPhase: String, Codable {
    case down
    case up
}

struct HotkeyEvent: Sendable {
    let action: HotkeyAction
    let phase: HotkeyPhase
}

struct ManagedBinding: Equatable {
    let action: HotkeyAction
    let binding: Keybind
}

struct Keybind: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var kind: KeybindKind
    var side: ModifierSide?

    init(keyCode: UInt16,
         modifiers: NSEvent.ModifierFlags = [],
         kind: KeybindKind = .combo,
         side: ModifierSide? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers.hotkeyRelevant
        self.kind = kind
        self.side = side
    }

    static let defaultPushToTalk = Keybind(keyCode: UInt16(kVK_Space), modifiers: [.option])
    static let defaultLongDictation = Keybind(keyCode: UInt16(kVK_Space), modifiers: [.option, .shift])
    static let leftShift = Keybind(keyCode: UInt16(kVK_Shift), kind: .standaloneKey, side: .left)
    static let rightShift = Keybind(keyCode: UInt16(kVK_RightShift), kind: .standaloneKey, side: .right)

    var displayString: String {
        switch kind {
        case .combo:
            return modifiers.symbolString + KeyCodeTranslator.shared.string(for: UInt32(keyCode))
        case .standaloneKey:
            return standaloneDisplayName
        }
    }

    var requiresEventTap: Bool {
        kind == .standaloneKey
    }

    var supportsCarbonHotkey: Bool {
        kind == .combo
    }

    private var standaloneDisplayName: String {
        switch keyCode {
        case UInt16(kVK_Shift): return "Left Shift"
        case UInt16(kVK_RightShift): return "Right Shift"
        case UInt16(kVK_Option): return "Left Option"
        case UInt16(kVK_RightOption): return "Right Option"
        case UInt16(kVK_Control): return "Left Control"
        case UInt16(kVK_RightControl): return "Right Control"
        case UInt16(kVK_Command): return "Left Command"
        case UInt16(kVK_RightCommand): return "Right Command"
        default:
            if let side {
                return "\(side == .left ? "Left" : "Right") \(KeyCodeTranslator.shared.string(for: UInt32(keyCode)))"
            }
            return KeyCodeTranslator.shared.string(for: UInt32(keyCode))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        kind = try container.decode(KeybindKind.self, forKey: .kind)
        side = try container.decodeIfPresent(ModifierSide.self, forKey: .side)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers).hotkeyRelevant
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(kind, forKey: .kind)
        try container.encode(side, forKey: .side)
        try container.encode(modifiers.hotkeyRelevant.rawValue, forKey: .modifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case kind
        case side
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.hotkeyRelevant.rawValue)
        hasher.combine(kind)
        hasher.combine(side)
    }
}

extension NSEvent.ModifierFlags {
    static let hotkeyRelevantMask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]

    var hotkeyRelevant: NSEvent.ModifierFlags {
        intersection(.hotkeyRelevantMask)
    }

    var symbolString: String {
        var symbols = ""
        if contains(.command) { symbols += "⌘" }
        if contains(.option) { symbols += "⌥" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.control) { symbols += "⌃" }
        return symbols
    }

    var carbonHotkeyModifiers: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}

extension Keybind {
    func matchesCombo(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        kind == .combo && self.keyCode == keyCode && self.modifiers.hotkeyRelevant == modifiers.hotkeyRelevant
    }
}
