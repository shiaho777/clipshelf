import Foundation

struct ClipboardContentIndexKey: Hashable {
    let type: ClipboardItem.ItemType
    let content: String
}

@MainActor
final class ClipboardHistoryIndex {
    private(set) var itemIndexByID: [UUID: Int] = [:]
    private(set) var itemIndexEpochByID: [UUID: Int] = [:]
    private(set) var itemByID: [UUID: ClipboardItem] = [:]
    private(set) var unpinnedIDsByContentKey: [ClipboardContentIndexKey: Set<UUID>] = [:]
    private(set) var unpinnedImageIDsByHash: [String: Set<UUID>] = [:]
    private(set) var imageFileReferenceCounts: [String: Int] = [:]
    private(set) var itemIndexByIDNeedsRebuild = false
    private(set) var unpinnedHeadInsertEpoch = 0
    private(set) var pendingUseCountsByID: [UUID: Int] = [:]

    func rebuild(from items: inout [ClipboardItem]) {
        applyPendingUseCounts(to: &items)
        itemIndexByID.removeAll(keepingCapacity: true)
        itemIndexEpochByID.removeAll(keepingCapacity: true)
        itemByID.removeAll(keepingCapacity: true)
        unpinnedIDsByContentKey.removeAll(keepingCapacity: true)
        unpinnedImageIDsByHash.removeAll(keepingCapacity: true)
        imageFileReferenceCounts.removeAll(keepingCapacity: true)
        itemIndexByIDNeedsRebuild = false
        unpinnedHeadInsertEpoch = 0

        for (index, item) in items.enumerated() {
            itemIndexByID[item.id] = index
            itemByID[item.id] = item
            indexUnpinnedLookup(item)
            if let fileName = item.imageFileName {
                imageFileReferenceCounts[fileName, default: 0] += 1
            }
        }
    }

    func applyPendingUseCounts(to items: inout [ClipboardItem]) {
        guard !pendingUseCountsByID.isEmpty else { return }
        if itemIndexByIDNeedsRebuild {
            for index in items.indices {
                if let useCount = pendingUseCountsByID[items[index].id] {
                    items[index].useCount = useCount
                }
            }
        } else {
            for (id, useCount) in pendingUseCountsByID {
                if let index = resolvedIndex(for: id),
                   index < items.count,
                   items[index].id == id {
                    items[index].useCount = useCount
                }
            }
        }
        pendingUseCountsByID.removeAll(keepingCapacity: true)
    }

    func index(for id: UUID, items: inout [ClipboardItem]) -> Int? {
        if itemIndexByIDNeedsRebuild {
            rebuild(from: &items)
        }
        guard let index = resolvedIndex(for: id) else { return nil }
        if index >= 0, index < items.count, items[index].id == id {
            return index
        }
        rebuild(from: &items)
        guard let rebuilt = itemIndexByID[id],
              rebuilt >= 0,
              rebuilt < items.count,
              items[rebuilt].id == id else {
            return nil
        }
        return rebuilt
    }

    func resolvedIndex(for id: UUID) -> Int? {
        guard let storedIndex = itemIndexByID[id],
              let item = itemByID[id] else { return nil }
        if item.isPinned {
            return storedIndex
        }
        let epoch = itemIndexEpochByID[id] ?? 0
        return storedIndex + max(0, unpinnedHeadInsertEpoch - epoch)
    }

    func remove(ids: Set<UUID>, removePendingUseCounts: Bool = true) {
        guard !ids.isEmpty else { return }
        for id in ids {
            if removePendingUseCounts {
                pendingUseCountsByID.removeValue(forKey: id)
            }
            guard let item = itemByID.removeValue(forKey: id) else { continue }
            itemIndexByID.removeValue(forKey: id)
            itemIndexEpochByID.removeValue(forKey: id)
            removeUnpinnedLookup(item)
            if let fileName = item.imageFileName,
               let count = imageFileReferenceCounts[fileName] {
                if count <= 1 {
                    imageFileReferenceCounts.removeValue(forKey: fileName)
                } else {
                    imageFileReferenceCounts[fileName] = count - 1
                }
            }
        }
    }

    func insert(_ item: ClipboardItem, at index: Int, itemsCount: Int, pinnedCount: Int) {
        if !itemIndexByIDNeedsRebuild && !item.isPinned && index == pinnedCount {
            unpinnedHeadInsertEpoch += 1
        } else if index < itemsCount - 1 {
            itemIndexByIDNeedsRebuild = true
        }
        itemIndexByID[item.id] = index
        if item.isPinned {
            itemIndexEpochByID.removeValue(forKey: item.id)
        } else {
            itemIndexEpochByID[item.id] = unpinnedHeadInsertEpoch
        }
        itemByID[item.id] = item
        indexUnpinnedLookup(item)
        if let fileName = item.imageFileName {
            imageFileReferenceCounts[fileName, default: 0] += 1
        }
    }

    func update(_ item: ClipboardItem, at index: Int, items: inout [ClipboardItem]) {
        var updatedItem = item
        if let useCount = pendingUseCountsByID[item.id] {
            updatedItem.useCount = useCount
            if index < items.count, items[index].id == item.id {
                items[index].useCount = useCount
            }
        }
        if let old = itemByID[updatedItem.id] {
            remove(ids: [old.id], removePendingUseCounts: false)
        }
        itemByID[updatedItem.id] = updatedItem
        itemIndexByID[updatedItem.id] = index
        if updatedItem.isPinned {
            itemIndexEpochByID.removeValue(forKey: updatedItem.id)
        } else {
            itemIndexEpochByID[updatedItem.id] = unpinnedHeadInsertEpoch
        }
        indexUnpinnedLookup(updatedItem)
        if let fileName = updatedItem.imageFileName {
            imageFileReferenceCounts[fileName, default: 0] += 1
        }
    }

    func setItem(_ item: ClipboardItem) {
        itemByID[item.id] = item
    }

    func markNeedsRebuild() {
        itemIndexByIDNeedsRebuild = true
    }

    func setPendingUseCount(_ useCount: Int, for id: UUID) {
        pendingUseCountsByID[id] = useCount
    }

    func clearPendingUseCount(for id: UUID) {
        pendingUseCountsByID.removeValue(forKey: id)
    }

    func hasOtherImageReferences(for fileName: String?) -> Bool {
        guard let fileName else { return false }
        return (imageFileReferenceCounts[fileName] ?? 0) > 0
    }

    private func indexUnpinnedLookup(_ item: ClipboardItem) {
        guard !item.isPinned else { return }
        switch item.type {
        case .text, .richText, .fileURL:
            unpinnedIDsByContentKey[ClipboardContentIndexKey(type: item.type, content: item.content), default: []].insert(item.id)
        case .image:
            if let hash = item.imageHash {
                unpinnedImageIDsByHash[hash, default: []].insert(item.id)
            }
        }
    }

    private func removeUnpinnedLookup(_ item: ClipboardItem) {
        guard !item.isPinned else { return }
        switch item.type {
        case .text, .richText, .fileURL:
            let key = ClipboardContentIndexKey(type: item.type, content: item.content)
            unpinnedIDsByContentKey[key]?.remove(item.id)
            if unpinnedIDsByContentKey[key]?.isEmpty == true {
                unpinnedIDsByContentKey.removeValue(forKey: key)
            }
        case .image:
            if let hash = item.imageHash {
                unpinnedImageIDsByHash[hash]?.remove(item.id)
                if unpinnedImageIDsByHash[hash]?.isEmpty == true {
                    unpinnedImageIDsByHash.removeValue(forKey: hash)
                }
            }
        }
    }
}
