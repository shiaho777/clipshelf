import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var category: String
    var shortcut: String?  // e.g. "/email" for text expansion
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, content: String, category: String = "", shortcut: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.shortcut = shortcut
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
