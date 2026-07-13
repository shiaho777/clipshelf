import Foundation

enum ClipboardHistoryQueries {
    static func recentContents(from items: [ClipboardItem], limit: Int) -> [String] {
        let boundedLimit = max(0, min(limit, items.count))
        guard boundedLimit > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(boundedLimit)
        for item in items.prefix(boundedLimit) {
            result.append(item.content)
        }
        return result
    }

    static func contents(
        from items: [ClipboardItem],
        sourceBundleID: String,
        limit: Int
    ) -> [String] {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(boundedLimit)
        for item in items where item.sourceBundleID == sourceBundleID {
            result.append(item.content)
            if result.count == boundedLimit { break }
        }
        return result
    }
}
