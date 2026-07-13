import Foundation

enum ClipboardEmbeddingPolicy {
    static let startupWarmLimit = 500

    static func isEligible(_ item: ClipboardItem) -> Bool {
        item.type != .image && !item.content.isEmpty && !item.isSensitive
    }

    static func startupWarmItems(from items: [ClipboardItem], limit: Int = startupWarmLimit) -> [ClipboardItem] {
        guard limit > 0 else { return [] }
        if items.count <= limit {
            return items
        }
        return Array(items.prefix(limit))
    }
}
