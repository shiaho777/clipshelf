import Foundation
import AppKit

private let timeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    
    init() { cache.countLimit = 50 }
    
    func image(for id: UUID, data: Data?) -> NSImage? {
        let key = id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = data, let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
    
    func remove(_ id: UUID) { cache.removeObject(forKey: id.uuidString as NSString) }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let imageData: Data?
    let rtfData: Data?
    let type: ItemType
    let timestamp: Date
    var isPinned: Bool
    
    enum ItemType: String, Codable { case text, image, richText }
    
    init(id: UUID = UUID(), content: String = "", imageData: Data? = nil, rtfData: Data? = nil, type: ItemType = .text, timestamp: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.content = content
        self.imageData = imageData
        self.rtfData = rtfData
        self.type = type
        self.timestamp = timestamp
        self.isPinned = isPinned
    }
    
    var displayContent: String {
        switch type {
        case .image: return "item.image".localized
        case .richText: return "item.richtext".localized
        case .text: return content.count > 50 ? String(content.prefix(50)) + "..." : content
        }
    }
    
    var displayText: String {
        content.count > 50 ? String(content.prefix(50)) + "..." : content
    }
    
    var cachedImage: NSImage? { ImageCache.shared.image(for: id, data: imageData) }
    
    var timeAgo: String { timeFormatter.localizedString(for: timestamp, relativeTo: Date()) }
}
