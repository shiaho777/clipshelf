import Foundation

enum ClipboardHistoryMaintenance {
    static func wipePayload(_ item: inout ClipboardItem) {
        let count = item.content.utf8.count
        item.content = String(repeating: "\0", count: count)
        item.imageData = nil
        item.rtfData = nil
    }

    static func expiredItems(in items: [ClipboardItem], now: Date = Date()) -> [ClipboardItem] {
        items.filter { item in
            guard let expiresAt = item.expiresAt else { return false }
            return expiresAt <= now
        }
    }

    static func sensitiveItems(in items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isSensitive)
    }

    static func autoCleanupCandidates(
        in items: [ClipboardItem],
        olderThan cutoff: Date
    ) -> [ClipboardItem] {
        items.filter { !$0.isPinned && $0.timestamp < cutoff }
    }

    static func autoCleanupCutoff(
        intervalDays: Int,
        now: Date = Date()
    ) -> Date? {
        guard intervalDays > 0 else { return nil }
        return now.addingTimeInterval(-Double(intervalDays) * 24 * 60 * 60)
    }

    static func unpinnedItems(in items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter { !$0.isPinned }
    }

    static func ocrMigrationCandidateIDs(
        in items: [ClipboardItem],
        limit: Int
    ) -> [UUID] {
        guard limit > 0 else { return [] }
        var result: [UUID] = []
        result.reserveCapacity(min(limit, items.count))
        for item in items {
            guard item.type == .image, item.ocrText == nil else { continue }
            result.append(item.id)
            if result.count == limit { break }
        }
        return result
    }

    static func additionalStoreIDs(
        _ storeIDs: Set<UUID>,
        excluding accounted: Set<UUID>
    ) -> Set<UUID> {
        storeIDs.subtracting(accounted)
    }

    struct ClearUnpinnedPlan {
        let removedItems: [ClipboardItem]
        let removedIDs: Set<UUID>
        let remainingItems: [ClipboardItem]
    }

    static func planClearUnpinned(items: [ClipboardItem]) -> ClearUnpinnedPlan {
        var removed: [ClipboardItem] = []
        var remaining: [ClipboardItem] = []
        removed.reserveCapacity(items.count)
        remaining.reserveCapacity(items.count)
        for item in items {
            if item.isPinned {
                remaining.append(item)
            } else {
                removed.append(item)
            }
        }
        return ClearUnpinnedPlan(
            removedItems: removed,
            removedIDs: Set(removed.map(\.id)),
            remainingItems: remaining
        )
    }
}

