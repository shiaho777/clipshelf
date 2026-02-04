import Foundation
import AppKit

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let imageData: Data?
    let type: ItemType
    let timestamp: Date
    var isPinned: Bool
    
    enum ItemType: String, Codable { case text, image }
    
    init(id: UUID = UUID(), content: String = "", imageData: Data? = nil, type: ItemType = .text, timestamp: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.content = content
        self.imageData = imageData
        self.type = type
        self.timestamp = timestamp
        self.isPinned = isPinned
    }
    
    var displayContent: String {
        if type == .image { return "item.image".localized }
        return content.count > 50 ? String(content.prefix(50)) + "..." : content
    }
    
    var displayText: String {
        content.count > 50 ? String(content.prefix(50)) + "..." : content
    }
    
    var image: NSImage? { imageData.flatMap { NSImage(data: $0) } }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
