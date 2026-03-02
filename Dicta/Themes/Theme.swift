import AppKit
import SwiftUI

struct Theme: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let primaryHex: String
    let backgroundHex: String
    let waveformHex: String
    let iconHex: String
}
