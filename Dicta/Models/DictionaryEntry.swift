import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var spoken: String
    var replacement: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         spoken: String,
         replacement: String,
         enabled: Bool = true,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.spoken = spoken
        self.replacement = replacement
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
