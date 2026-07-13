import Foundation
import os

protocol ClipboardHistoryStore {
    func loadItems() throws -> [ClipboardItem]
    func loadItems(limit: Int?) throws -> [ClipboardItem]
    func itemCount() throws -> Int
    func loadItem(id: UUID) throws -> ClipboardItem?
    @discardableResult
    func saveItems(_ items: [ClipboardItem]) throws -> Bool
    @discardableResult
    func upsertItem(_ item: ClipboardItem) throws -> Bool
    @discardableResult
    func deleteItems(ids: Set<UUID>) throws -> Bool
    @discardableResult
    func updateUseCount(id: UUID, useCount: Int) throws -> Bool
    @discardableResult
    func updateUseCounts(_ useCountsByID: [UUID: Int]) throws -> Bool
    @discardableResult
    func trimUnpinned(to maxUnpinned: Int) throws -> Set<UUID>
    @discardableResult
    func deleteUnpinned() throws -> Set<UUID>
    @discardableResult
    func deleteExpired(before date: Date) throws -> Set<UUID>
    @discardableResult
    func deleteUnpinnedOlderThan(_ date: Date) throws -> Set<UUID>
    func searchFTS(_ query: String, limit: Int) -> [UUID]
}

extension ClipboardHistoryStore {
    func loadItems() throws -> [ClipboardItem] { try loadItems(limit: nil) }

    func itemCount() throws -> Int { try loadItems(limit: nil).count }

    func loadItem(id: UUID) throws -> ClipboardItem? {
        try loadItems(limit: nil).first { $0.id == id }
    }

    @discardableResult
    func upsertItem(_ item: ClipboardItem) throws -> Bool { try saveItems([item]) }

    @discardableResult
    func deleteItems(ids: Set<UUID>) throws -> Bool { false }

    @discardableResult
    func updateUseCount(id: UUID, useCount: Int) throws -> Bool { false }

    @discardableResult
    func updateUseCounts(_ useCountsByID: [UUID: Int]) throws -> Bool {
        var changed = false
        for (id, useCount) in useCountsByID {
            changed = (try updateUseCount(id: id, useCount: useCount)) || changed
        }
        return changed
    }

    @discardableResult
    func trimUnpinned(to maxUnpinned: Int) throws -> Set<UUID> {
        let items = try loadItems(limit: nil)
        let unpinned = items.filter { !$0.isPinned }
        guard unpinned.count > maxUnpinned else { return [] }
        let removed = Array(unpinned.suffix(unpinned.count - maxUnpinned))
        let ids = Set(removed.map(\.id))
        _ = try deleteItems(ids: ids)
        return ids
    }

    @discardableResult
    func deleteUnpinned() throws -> Set<UUID> {
        let items = try loadItems(limit: nil)
        let ids = Set(items.filter { !$0.isPinned }.map(\.id))
        _ = try deleteItems(ids: ids)
        return ids
    }

    @discardableResult
    func deleteExpired(before date: Date) throws -> Set<UUID> {
        let items = try loadItems(limit: nil)
        let ids = Set(items.compactMap { item -> UUID? in
            guard let expiresAt = item.expiresAt, expiresAt <= date else { return nil }
            return item.id
        })
        _ = try deleteItems(ids: ids)
        return ids
    }

    @discardableResult
    func deleteUnpinnedOlderThan(_ date: Date) throws -> Set<UUID> {
        let items = try loadItems(limit: nil)
        let ids = Set(items.filter { !$0.isPinned && $0.timestamp < date }.map(\.id))
        _ = try deleteItems(ids: ids)
        return ids
    }

    func searchFTS(_ query: String, limit: Int = 500) -> [UUID] { [] }
}

final class JSONClipboardHistoryStore: ClipboardHistoryStore {
    private let fileURL: URL
    private var lastSavedItems: [ClipboardItem]?
    private var lastSavedData: Data?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "HistoryStore")
    static let backupCount = 3
    
    init(storageDirectory: URL) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        self.fileURL = storageDirectory.appendingPathComponent("history.json")
    }
    
    func loadItems(limit: Int? = nil) throws -> [ClipboardItem] {
        let items: [ClipboardItem]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                items = try decoder.decode([ClipboardItem].self, from: data)
                lastSavedItems = items
                lastSavedData = data
            } catch {
                logger.error("Failed to decode history.json: \(error.localizedDescription). Attempting backup recovery.")
                if let recovered = recoverFromBackup() {
                    lastSavedItems = recovered
                    lastSavedData = nil
                    items = recovered
                } else {
                    throw error
                }
            }
        } else {
            items = []
        }
        guard let limit, limit >= 0, items.count > limit else { return items }
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        for item in items {
            if item.isPinned { pinned.append(item) } else { unpinned.append(item) }
        }
        let keepUnpinned = max(0, limit - pinned.count)
        return pinned + Array(unpinned.prefix(keepUnpinned))
    }

    func itemCount() throws -> Int {
        if let lastSavedItems { return lastSavedItems.count }
        return try loadItems(limit: nil).count
    }

    func loadItem(id: UUID) throws -> ClipboardItem? {
        if let item = lastSavedItems?.first(where: { $0.id == id }) { return item }
        return try loadItems(limit: nil).first { $0.id == id }
    }
    
    @discardableResult
    func saveItems(_ items: [ClipboardItem]) throws -> Bool {
        if items == lastSavedItems {
            return false
        }
        let encoded = try encoder.encode(items)
        if encoded == lastSavedData {
            return false
        }
        rotateBackups()
        try encoded.write(to: fileURL, options: .atomic)
        lastSavedItems = items
        lastSavedData = encoded
        return true
    }

    @discardableResult
    func upsertItem(_ item: ClipboardItem) throws -> Bool {
        var current = lastSavedItems ?? (try? loadItems()) ?? []
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            current[index] = item
        } else {
            current.insert(item, at: 0)
        }
        return try saveItems(current)
    }

    @discardableResult
    func deleteItems(ids: Set<UUID>) throws -> Bool {
        guard !ids.isEmpty else { return false }
        var current = lastSavedItems ?? (try? loadItems()) ?? []
        let previousCount = current.count
        current.removeAll { ids.contains($0.id) }
        guard current.count != previousCount else { return false }
        return try saveItems(current)
    }

    @discardableResult
    func updateUseCount(id: UUID, useCount: Int) throws -> Bool {
        var current = lastSavedItems ?? (try? loadItems()) ?? []
        guard let index = current.firstIndex(where: { $0.id == id }),
              current[index].useCount != useCount else { return false }
        current[index].useCount = useCount
        return try saveItems(current)
    }
    
    // MARK: - Backup Rotation
    
    func backupURL(_ index: Int) -> URL {
        fileURL.appendingPathExtension("bak.\(index)")
    }
    
    private func rotateBackups() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        // Rotate: delete .bak.3, move .bak.2 -> .bak.3, .bak.1 -> .bak.2, copy current -> .bak.1
        for i in stride(from: Self.backupCount, through: 2, by: -1) {
            let dst = backupURL(i)
            let src = backupURL(i - 1)
            try? fm.removeItem(at: dst)
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        try? fm.copyItem(at: fileURL, to: backupURL(1))
    }
    
    private func recoverFromBackup() -> [ClipboardItem]? {
        for i in 1...Self.backupCount {
            let url = backupURL(i)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let items = try decoder.decode([ClipboardItem].self, from: data)
                logger.info("Recovered \(items.count) items from backup .bak.\(i)")
                return items
            } catch {
                logger.warning("Backup .bak.\(i) also corrupted: \(error.localizedDescription)")
                continue
            }
        }
        logger.error("All backups corrupted or missing. No recovery possible.")
        return nil
    }
}
