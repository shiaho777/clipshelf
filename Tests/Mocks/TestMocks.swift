import Foundation
@testable import ClipboardManager

// MARK: - InMemoryClipboardHistoryStore

final class InMemoryClipboardHistoryStore: ClipboardHistoryStore {
    private let lock = NSLock()
    private var storage: [ClipboardItem] = []
    private(set) var saveCallCount = 0
    private(set) var updateUseCountCallCount = 0

    var items: [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func seed(_ items: [ClipboardItem]) {
        lock.lock(); defer { lock.unlock() }
        storage = items
    }

    func loadItems(limit: Int?) throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        guard let limit, limit >= 0, storage.count > limit else { return storage }
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        for item in storage {
            if item.isPinned { pinned.append(item) } else { unpinned.append(item) }
        }
        let keep = max(0, limit - pinned.count)
        return pinned + Array(unpinned.prefix(keep))
    }

    func itemCount() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    func loadItem(id: UUID) throws -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        return storage.first { $0.id == id }
    }

    @discardableResult
    func trimUnpinned(to maxUnpinned: Int) throws -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let bounded = max(0, maxUnpinned)
        let unpinned = storage.filter { !$0.isPinned }
        guard unpinned.count > bounded else { return [] }
        let removed = Array(unpinned.suffix(unpinned.count - bounded))
        let ids = Set(removed.map(\.id))
        storage.removeAll { ids.contains($0.id) }
        return ids
    }

    @discardableResult
    func deleteUnpinned() throws -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(storage.filter { !$0.isPinned }.map(\.id))
        storage.removeAll { ids.contains($0.id) }
        return ids
    }

    @discardableResult
    func deleteExpired(before date: Date) throws -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(storage.compactMap { item -> UUID? in
            guard let expiresAt = item.expiresAt, expiresAt <= date else { return nil }
            return item.id
        })
        storage.removeAll { ids.contains($0.id) }
        return ids
    }

    @discardableResult
    func deleteUnpinnedOlderThan(_ date: Date) throws -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(storage.filter { !$0.isPinned && $0.timestamp < date }.map(\.id))
        storage.removeAll { ids.contains($0.id) }
        return ids
    }

    @discardableResult
    func saveItems(_ items: [ClipboardItem]) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        saveCallCount += 1
        storage = items
        return true
    }

    @discardableResult
    func upsertItem(_ item: ClipboardItem) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        saveCallCount += 1
        if let index = storage.firstIndex(where: { $0.id == item.id }) {
            storage[index] = item
        } else {
            storage.insert(item, at: 0)
        }
        return true
    }

    @discardableResult
    func deleteItems(ids: Set<UUID>) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !ids.isEmpty else { return false }
        let previousCount = storage.count
        storage.removeAll { ids.contains($0.id) }
        guard storage.count != previousCount else { return false }
        saveCallCount += 1
        return true
    }

    @discardableResult
    func updateUseCount(id: UUID, useCount: Int) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return false }
        storage[index].useCount = useCount
        updateUseCountCallCount += 1
        saveCallCount += 1
        return true
    }

    @discardableResult
    func updateUseCounts(_ useCountsByID: [UUID: Int]) throws -> Bool {
        var changed = false
        for (id, useCount) in useCountsByID {
            changed = (try updateUseCount(id: id, useCount: useCount)) || changed
        }
        return changed
    }
}

// MARK: - InMemoryClipboardImageStore

final class InMemoryClipboardImageStore: ClipboardImageStore {
    private(set) var storage: [String: Data] = [:]
    private(set) var deletedFileNames: [String] = []
    private(set) var prunedOrphanFileNames: [String] = []

    func fileURL(for fileName: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    }

    func imageData(for fileName: String) -> Data? { storage[fileName] }

    func saveImageData(_ data: Data, fileName: String) throws {
        storage[fileName] = data
    }

    func deleteImageFile(named fileName: String) {
        storage.removeValue(forKey: fileName)
        deletedFileNames.append(fileName)
    }

    func pruneOrphanedFiles(referencedFileNames: Set<String>) {
        let orphans = Set(storage.keys).subtracting(referencedFileNames)
        prunedOrphanFileNames.append(contentsOf: orphans)
        for orphan in orphans { storage.removeValue(forKey: orphan) }
    }
}

// MARK: - InMemoryAppPreferencesStore

final class InMemoryAppPreferencesStore: AppPreferencesStore {
    var language: String?
    var launchAtLogin: Bool?
    var maxHistoryCount: Int?
    var autoCleanupInterval: Int?
    var excludedBundleIDs: Set<String>?
    var smartPasteEnabled: Bool?
    var hotWindowCount: Int?

    func loadLanguage() throws -> String? { language }
    @discardableResult func saveLanguage(_ language: String) throws -> Bool { self.language = language; return true }

    func loadLaunchAtLogin() throws -> Bool? { launchAtLogin }
    @discardableResult func saveLaunchAtLogin(_ enabled: Bool) throws -> Bool { launchAtLogin = enabled; return true }

    func loadMaxHistoryCount() throws -> Int? { maxHistoryCount }
    @discardableResult func saveMaxHistoryCount(_ value: Int) throws -> Bool { maxHistoryCount = value; return true }

    func loadAutoCleanupInterval() throws -> Int? { autoCleanupInterval }
    @discardableResult func saveAutoCleanupInterval(_ value: Int) throws -> Bool { autoCleanupInterval = value; return true }

    func loadExcludedBundleIDs() throws -> Set<String>? { excludedBundleIDs }
    @discardableResult func saveExcludedBundleIDs(_ bundleIDs: Set<String>) throws -> Bool { excludedBundleIDs = bundleIDs; return true }

    func loadSmartPasteEnabled() throws -> Bool? { smartPasteEnabled }
    @discardableResult func saveSmartPasteEnabled(_ enabled: Bool) throws -> Bool { smartPasteEnabled = enabled; return true }

    func loadHotWindowCount() throws -> Int? { hotWindowCount }
    @discardableResult func saveHotWindowCount(_ value: Int) throws -> Bool { hotWindowCount = value; return true }
}

// MARK: - InMemoryHotKeyStore

final class InMemoryHotKeyStore: HotKeyStore {
    var config: HotKeyConfig?
    var queueConfig: HotKeyConfig?
    var quickPasteConfig: HotKeyConfig?

    func loadMainHotKey() throws -> HotKeyConfig? { config }

    @discardableResult
    func saveMainHotKey(_ config: HotKeyConfig) throws -> Bool {
        self.config = config
        return true
    }
    
    func loadQueueHotKey() throws -> HotKeyConfig? { queueConfig }
    
    @discardableResult
    func saveQueueHotKey(_ config: HotKeyConfig) throws -> Bool {
        self.queueConfig = config
        return true
    }

    func loadQuickPasteHotKey() throws -> HotKeyConfig? { quickPasteConfig }

    @discardableResult
    func saveQuickPasteHotKey(_ config: HotKeyConfig) throws -> Bool {
        self.quickPasteConfig = config
        return true
    }
}

// MARK: - InMemoryOCRService

final class InMemoryOCRService: OCRServiceProtocol {
    var resultToReturn: String?
    var holdCompletions = false
    private(set) var completions: [(String?) -> Void] = []

    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        if holdCompletions {
            completions.append(completion)
            return
        }
        completion(resultToReturn)
    }

    func completeAll() {
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(resultToReturn) }
    }

    func completeNext() {
        guard !completions.isEmpty else { return }
        let callback = completions.removeFirst()
        callback(resultToReturn)
    }
}

// MARK: - MockLaunchAtLoginService

final class MockLaunchAtLoginService: LaunchAtLoginService {
    private(set) var setEnabledCalls: [Bool] = []
    var errorToThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let error = errorToThrow { throw error }
    }
}
