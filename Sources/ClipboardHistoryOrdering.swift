import Foundation

enum ClipboardHistoryOrdering {
    static func partitionPinned(_ items: [ClipboardItem]) -> (pinned: [ClipboardItem], unpinned: [ClipboardItem]) {
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        pinned.reserveCapacity(items.count)
        unpinned.reserveCapacity(items.count)
        for item in items {
            if item.isPinned {
                pinned.append(item)
            } else {
                unpinned.append(item)
            }
        }
        return (pinned, unpinned)
    }

    static func reorderedByPinState(_ items: [ClipboardItem]) -> (items: [ClipboardItem], pinnedCount: Int) {
        let parts = partitionPinned(items)
        return (parts.pinned + parts.unpinned, parts.pinned.count)
    }

    static func enforceHotWindow(_ items: [ClipboardItem], hotWindowCount: Int) -> [ClipboardItem]? {
        let parts = partitionPinned(items)
        let keepUnpinned = max(0, hotWindowCount - parts.pinned.count)
        guard parts.unpinned.count > keepUnpinned else { return nil }
        return parts.pinned + Array(parts.unpinned.prefix(keepUnpinned))
    }

    static func mergeMissingByPinAndTimestamp(
        existing: [ClipboardItem],
        missing: [ClipboardItem]
    ) -> [ClipboardItem] {
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        pinned.reserveCapacity(existing.count + missing.count)
        unpinned.reserveCapacity(existing.count + missing.count)
        for item in existing {
            if item.isPinned { pinned.append(item) } else { unpinned.append(item) }
        }
        for item in missing {
            if item.isPinned { pinned.append(item) } else { unpinned.append(item) }
        }
        pinned.sort { $0.timestamp > $1.timestamp }
        unpinned.sort { $0.timestamp > $1.timestamp }
        return pinned + unpinned
    }

    static func mergeByTimestampDescending(
        existing: [ClipboardItem],
        incoming: [ClipboardItem]
    ) -> [ClipboardItem] {
        guard !incoming.isEmpty else { return existing }
        var existingIterator = existing.makeIterator()
        var existingItem = existingIterator.next()
        var incomingIndex = 0
        var result: [ClipboardItem] = []
        result.reserveCapacity(existing.count + incoming.count)
        while let currentExisting = existingItem, incomingIndex < incoming.count {
            if incoming[incomingIndex].timestamp > currentExisting.timestamp {
                result.append(incoming[incomingIndex])
                incomingIndex += 1
            } else {
                result.append(currentExisting)
                existingItem = existingIterator.next()
            }
        }
        while let currentExisting = existingItem {
            result.append(currentExisting)
            existingItem = existingIterator.next()
        }
        if incomingIndex < incoming.count {
            result.append(contentsOf: incoming[incomingIndex...])
        }
        return result
    }

    static func trimUnpinnedInMemory(
        _ items: [ClipboardItem],
        maxHistoryCount: Int,
        pinnedCount: Int
    ) -> (items: [ClipboardItem], removed: [ClipboardItem])? {
        guard maxHistoryCount > 0 else { return nil }
        let pc = min(max(0, pinnedCount), items.count)
        let maxUnpinned = max(0, maxHistoryCount - pc)
        let unpinnedCount = max(0, items.count - pc)
        guard unpinnedCount > maxUnpinned else { return nil }
        let removeCount = min(unpinnedCount - maxUnpinned, items.count)
        guard removeCount > 0 else { return nil }
        let removed = Array(items.suffix(removeCount))
        let kept = Array(items.dropLast(removeCount))
        return (kept, removed)
    }

    static func mergeFetched(
        existing: [ClipboardItem],
        pinnedCount: Int,
        incoming: [ClipboardItem]
    ) -> [ClipboardItem] {
        guard !incoming.isEmpty else { return existing }
        let partitionedIncoming = partitionPinned(incoming)
        let sortedPinned = partitionedIncoming.pinned.sorted { $0.timestamp > $1.timestamp }
        let sortedUnpinned = partitionedIncoming.unpinned.sorted { $0.timestamp > $1.timestamp }
        let existingPinnedEnd = min(max(0, pinnedCount), existing.count)
        let existingPinned = Array(existing[..<existingPinnedEnd])
        let existingUnpinned = Array(existing[existingPinnedEnd...])
        let mergedPinned = mergeByTimestampDescending(
            existing: existingPinned,
            incoming: sortedPinned
        )
        let mergedUnpinned = mergeByTimestampDescending(
            existing: existingUnpinned,
            incoming: sortedUnpinned
        )
        return mergedPinned + mergedUnpinned
    }

    static func reorderedAfterTogglingPin(
        items: [ClipboardItem],
        at index: Int
    ) -> (items: [ClipboardItem], pinnedCount: Int, updated: ClipboardItem)? {
        guard items.indices.contains(index) else { return nil }
        var next = items
        next[index].isPinned.toggle()
        let reordered = reorderedByPinState(next)
        guard let updated = reordered.items.first(where: { $0.id == items[index].id }) else {
            return nil
        }
        return (reordered.items, reordered.pinnedCount, updated)
    }

    static func maxUnpinnedCapacity(
        maxHistoryCount: Int,
        pinnedCount: Int,
        itemCount: Int
    ) -> Int {
        guard maxHistoryCount > 0 else { return 0 }
        let pc = min(max(0, pinnedCount), itemCount)
        return max(0, maxHistoryCount - pc)
    }

    static func movingItem(
        id: UUID,
        toDestinationID destinationID: UUID,
        in items: [ClipboardItem],
        placeBefore: Bool
    ) -> [ClipboardItem]? {
        guard id != destinationID,
              let from = items.firstIndex(where: { $0.id == id }),
              items.contains(where: { $0.id == destinationID })
        else { return nil }

        var next = items
        let item = next.remove(at: from)
        guard let dest = next.firstIndex(where: { $0.id == destinationID }) else { return nil }
        let insertAt = placeBefore ? dest : min(dest + 1, next.count)

        if item.isPinned {
            let pinnedCount = next.reduce(0) { $0 + ($1.isPinned ? 1 : 0) }
            let clamped = min(max(0, insertAt), pinnedCount)
            next.insert(item, at: clamped)
        } else {
            let firstUnpinned = next.firstIndex(where: { !$0.isPinned }) ?? next.count
            let clamped = min(max(firstUnpinned, insertAt), next.count)
            next.insert(item, at: clamped)
        }
        return next
    }
}
