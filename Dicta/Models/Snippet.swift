import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String,
         content: String,
         tags: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
