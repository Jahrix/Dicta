import Foundation

struct StyleProfile: Identifiable, Codable, Equatable {
    enum CasingMode: String, Codable, CaseIterable, Identifiable {
        case `default`
        case sentence
        case lower
        case none

        var id: String { rawValue }
    }

    enum DashStyle: String, Codable, CaseIterable, Identifiable {
        case hyphen
        case emDash
        case enDash

        var id: String { rawValue }
    }

    var id: UUID
    var name: String
    var appBundleIDs: [String]
    var smartPunctuationEnabled: Bool
    var spokenPunctuationEnabled: Bool
    var phraseMapEnabled: Bool
    var casingMode: CasingMode
    var dashStyle: DashStyle
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         appBundleIDs: [String] = [],
         smartPunctuationEnabled: Bool = true,
         spokenPunctuationEnabled: Bool = true,
         phraseMapEnabled: Bool = true,
         casingMode: CasingMode = .default,
         dashStyle: DashStyle = .hyphen,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.appBundleIDs = appBundleIDs
        self.smartPunctuationEnabled = smartPunctuationEnabled
        self.spokenPunctuationEnabled = spokenPunctuationEnabled
        self.phraseMapEnabled = phraseMapEnabled
        self.casingMode = casingMode
        self.dashStyle = dashStyle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
