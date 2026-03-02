import Foundation

enum RoyalThemes {
    static let all: [Theme] = [
        Theme(id: "imperial-gold", name: "Imperial Gold", primaryHex: "#F2C14E", backgroundHex: "#21170A", waveformHex: "#FFD978", iconHex: "#FFF4D1"),
        Theme(id: "cobalt-crown", name: "Cobalt Crown", primaryHex: "#4F6DFF", backgroundHex: "#11162E", waveformHex: "#88A0FF", iconHex: "#EEF2FF"),
        Theme(id: "emerald-court", name: "Emerald Court", primaryHex: "#1FA971", backgroundHex: "#0D231C", waveformHex: "#55D7A0", iconHex: "#E6FFF5"),
        Theme(id: "crimson-velvet", name: "Crimson Velvet", primaryHex: "#BE3144", backgroundHex: "#2A1016", waveformHex: "#E66578", iconHex: "#FFE7EB"),
        Theme(id: "amethyst-hall", name: "Amethyst Hall", primaryHex: "#8B5CF6", backgroundHex: "#1F1633", waveformHex: "#B395FF", iconHex: "#F2EBFF"),
        Theme(id: "sapphire-crest", name: "Sapphire Crest", primaryHex: "#1D4ED8", backgroundHex: "#0E1A37", waveformHex: "#5A86FF", iconHex: "#EAF0FF"),
        Theme(id: "rose-regent", name: "Rose Regent", primaryHex: "#E05C8C", backgroundHex: "#31141F", waveformHex: "#FFA0BF", iconHex: "#FFF0F6"),
        Theme(id: "obsidian-gold", name: "Obsidian Gold", primaryHex: "#D4A017", backgroundHex: "#101010", waveformHex: "#F3C857", iconHex: "#FFF5DA"),
        Theme(id: "ivory-navy", name: "Ivory Navy", primaryHex: "#E8E1D4", backgroundHex: "#172033", waveformHex: "#FFF7E7", iconHex: "#FFFFFF"),
        Theme(id: "forest-brass", name: "Forest Brass", primaryHex: "#8DAA36", backgroundHex: "#18200E", waveformHex: "#B8D467", iconHex: "#F4F9E4"),
        Theme(id: "royal-plum", name: "Royal Plum", primaryHex: "#6F2DBD", backgroundHex: "#190F28", waveformHex: "#A66CFF", iconHex: "#F1E7FF"),
        Theme(id: "copper-ember", name: "Copper Ember", primaryHex: "#C56A3D", backgroundHex: "#28140E", waveformHex: "#F49B6C", iconHex: "#FFF0E9"),
        Theme(id: "teal-palace", name: "Teal Palace", primaryHex: "#0F8B8D", backgroundHex: "#0D2021", waveformHex: "#4FCED0", iconHex: "#E9FFFF"),
        Theme(id: "burgundy-ink", name: "Burgundy Ink", primaryHex: "#7D1538", backgroundHex: "#1E0E15", waveformHex: "#C94E7A", iconHex: "#FFF0F5"),
        Theme(id: "silver-midnight", name: "Silver Midnight", primaryHex: "#B8C0CC", backgroundHex: "#161A20", waveformHex: "#E1E7EF", iconHex: "#FFFFFF"),
        Theme(id: "onyx-orchid", name: "Onyx Orchid", primaryHex: "#B33DCF", backgroundHex: "#140F19", waveformHex: "#DF81F2", iconHex: "#FFF0FF")
    ]

    static let defaultTheme = all.first { $0.id == "cobalt-crown" } ?? all[0]
}
