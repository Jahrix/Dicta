import AppKit
import SwiftUI

enum ThemeManager {
    static func normalizedHex(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#\(hex)"
    }

    static func effectiveTheme(selectedID: String, customHexEnabled: Bool, customHex: String) -> Theme {
        let base = RoyalThemes.all.first(where: { $0.id == selectedID }) ?? RoyalThemes.defaultTheme
        guard customHexEnabled, let hex = normalizedHex(customHex), let color = color(from: hex) else {
            return base
        }
        let background = color.blended(withFraction: 0.78, of: .black) ?? color
        let waveform = color.blended(withFraction: 0.25, of: .white) ?? color
        let icon = color.blended(withFraction: 0.82, of: .white) ?? .white
        return Theme(id: "custom-\(hex)",
                     name: "Custom",
                     primaryHex: hex,
                     backgroundHex: background.hexString ?? base.backgroundHex,
                     waveformHex: waveform.hexString ?? hex,
                     iconHex: icon.hexString ?? "#FFFFFF")
    }

    static func color(from hex: String) -> NSColor? {
        guard let normalized = normalizedHex(hex) else { return nil }
        let scanner = Scanner(string: String(normalized.dropFirst()))
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else { return nil }
        let red = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(value & 0x0000FF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    static func swiftUIColor(from hex: String) -> Color {
        Color(nsColor: color(from: hex) ?? .controlAccentColor)
    }
}

private extension NSColor {
    var hexString: String? {
        guard let color = usingColorSpace(.deviceRGB) else { return nil }
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
