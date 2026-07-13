import Foundation
import AppKit
import SwiftUI
import os

@MainActor
class ClipboardManager: ObservableObject {
    private enum Defaults {
        static let maxHistoryCount = 50_000
        static let autoCleanupInterval = 0
        static let hotWindowCount = 2_000
    }

    @Published var items: [ClipboardItem] = []
    @Published var maxHistoryCount: Int = Defaults.maxHistoryCount {
        didSet {
            guard oldValue != maxHistoryCount else { return }
            trimToLimit()
            saveItems()
            prefs.saveMaxHistoryCount(maxHistoryCount)
        }
    }
    @Published var autoCleanupInterval: Int = Defaults.autoCleanupInterval {
        didSet {
            guard oldValue != autoCleanupInterval else { return }
            configureCleanupTimer()
            cleanupOldItems()
            prefs.saveAutoCleanupInterval(autoCleanupInterval)
        }
    }
    @Published var smartPasteEnabled: Bool = true {
        didSet {
            guard oldValue != smartPasteEnabled else { return }
            prefs.saveSmartPasteEnabled(smartPasteEnabled)
        }
    }
    /// Set to the adapter name when Smart Paste transforms a copy; reset to nil after the consumer
    /// (AppDelegate) handles it. Used to drive the status-bar feedback badge.
    @Published var lastSmartPasteDescription: String?
    @Published private(set) var historyRevision: UInt64 = 0
    @Published private(set) var totalStoredCount: Int = 0
    @Published var hotWindowCount: Int = Defaults.hotWindowCount {
        didSet {
            let normalized = Self.normalizedHotWindowCount(hotWindowCount)
            if normalized != hotWindowCount {
                hotWindowCount = normalized
                return
            }
            guard oldValue != hotWindowCount else { return }
            if isInitializing { return }
            prefs.saveHotWindowCount(hotWindowCount)
            if hotWindowCount > oldValue {
                expandHotWindowIfNeeded()
            } else {
                enforceHotWindowInMemory()
            }
            noteHistoryMutation()
        }
    }
    var targetBundleID: String?
    var onItemSelected: (() -> Void)?
    
    private let pasteboard = NSPasteboard.general
    private var cleanupTimer: Timer?
    private var cachedExcludedBundleIDs: Set<String> = ClipboardManager.defaultExcludedBundleIDs
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "Storage")
    private let storageDirectory: URL
    private let historyStore: ClipboardHistoryStore
    private let monitor: ClipboardMonitor
    private let persistence: ClipboardPersistenceCoordinator
    let ruleEngine = ClipboardRuleEngine()
    private let ruleStore: ClipboardRuleStore
    private var embeddingCache: [UUID: [Float32]] = [:]
    private let startupOCRMigrationLimit = 24
    private var pasteboardDataProviders: [NSPasteboardItemDataProvider] = []
    private let historyIndex = ClipboardHistoryIndex()
    private var ocrQueue: ClipboardOCRQueue!

    // Extracted sub-managers (facade pattern)
    let imageManager: ClipboardImageManager
    private let prefs: ClipboardPreferencesManager
    private let syncCoordinator: ClipboardSyncCoordinator
    private var ingestPipeline: ClipboardIngestPipeline!
    private var captureDispatcher: ClipboardCaptureDispatcher!
    private var isInitializing = true
    private var deletedIDTombstones: Set<UUID> = []
    private var suppressItemsPublish = false

    var pendingOCRQueueDepth: Int { ocrQueue?.depth ?? 0 }
    private var itemByID: [UUID: ClipboardItem] { historyIndex.itemByID }
    
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane"
    ]
    
    var excludedBundleIDs: Set<String> {
        get { cachedExcludedBundleIDs }
        set {
            guard newValue != cachedExcludedBundleIDs else { return }
            cachedExcludedBundleIDs = newValue
            monitor.excludedBundleIDs = newValue
            persistExcludedBundleIDs()
        }
    }
    
    private var cachedPinnedCount: Int = 0
    private var pinnedCount: Int { cachedPinnedCount }
    private var cloudDeleteObserver: NSObjectProtocol?

    private func rebuildItemIndexes() {
        historyIndex.rebuild(from: &items)
    }

    private func applyPendingUseCountsToItems() {
        historyIndex.applyPendingUseCounts(to: &items)
    }

    private func indexForItem(id: UUID) -> Int? {
        historyIndex.index(for: id, items: &items)
    }

    private func removeIDsFromIndexes(_ ids: Set<UUID>, removePendingUseCounts: Bool = true) {
        historyIndex.remove(ids: ids, removePendingUseCounts: removePendingUseCounts)
    }

    private func insertItemIntoIndexes(_ item: ClipboardItem, at index: Int) {
        deletedIDTombstones.remove(item.id)
        historyIndex.insert(item, at: index, itemsCount: items.count, pinnedCount: cachedPinnedCount)
    }

    private func updateIndexedItem(_ item: ClipboardItem, at index: Int) {
        historyIndex.update(item, at: index, items: &items)
    }

    private func deleteItemsFromMemory(ids: Set<UUID>) -> [ClipboardItem] {
        guard !ids.isEmpty else { return [] }
        var removed: [ClipboardItem] = []
        if ids.count <= 16 {
            var offsets: [(index: Int, item: ClipboardItem)] = []
            offsets.reserveCapacity(ids.count)
            for id in ids {
                if let index = indexForItem(id: id) {
                    offsets.append((index, items[index]))
                }
            }
            for pair in offsets.sorted(by: { $0.index > $1.index }) {
                items.remove(at: pair.index)
                removed.append(pair.item)
            }
            if !offsets.isEmpty {
                historyIndex.markNeedsRebuild()
            }
        } else {
            items.removeAll { item in
                guard ids.contains(item.id) else { return false }
                removed.append(item)
                return true
            }
            if !removed.isEmpty {
                historyIndex.markNeedsRebuild()
            }
        }
        if !removed.isEmpty {
            let removedIDs = Set(removed.map(\.id))
            removeIDsFromIndexes(removedIDs)
            ocrQueue?.remove(ids: ids)
            recomputePinnedCount()
            totalStoredCount = max(0, totalStoredCount - removed.count)
            deletedIDTombstones.formUnion(removedIDs)
            if deletedIDTombstones.count > 5_000 {
                deletedIDTombstones = Set(removedIDs)
            }
        }
        return removed
    }

    private func removeHistoryItems(_ targets: [ClipboardItem], wipeFirst: Bool = false) {
        guard !targets.isEmpty else { return }
        if wipeFirst {
            for item in targets {
                var wiped = item
                ClipboardHistoryMaintenance.wipePayload(&wiped)
                if let index = indexForItem(id: item.id) {
                    items[index] = wiped
                } else if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = wiped
                }
            }
        }
        let ids = Set(targets.map(\.id))
        var removed = deleteItemsFromMemory(ids: ids)
        if removed.count != targets.count {
            let remainingIDs = ids.subtracting(Set(removed.map(\.id)))
            if !remainingIDs.isEmpty {
                let fallback = items.filter { remainingIDs.contains($0.id) }
                items.removeAll { remainingIDs.contains($0.id) }
                removeIDsFromIndexes(remainingIDs)
                ocrQueue?.remove(ids: remainingIDs)
                recomputePinnedCount()
                totalStoredCount = max(0, totalStoredCount - fallback.count)
                deletedIDTombstones.formUnion(remainingIDs)
                removed.append(contentsOf: fallback)
                rebuildItemIndexes()
            }
        }
        deleteImageFiles(for: removed)
        persistDeletedIDsIncrementally(ids)
        noteHistoryMutation()
    }

    private func incrementUseCount(for id: UUID) {
        guard var item = resolveItemIncludingColdStorage(id: id) else { return }
        let useCount = (historyIndex.pendingUseCountsByID[id] ?? item.useCount) + 1
        item.useCount = useCount
        historyIndex.setItem(item)
        historyIndex.setPendingUseCount(useCount, for: id)
        if let index = indexForItem(id: id), index < items.count, items[index].id == id {
            items[index].useCount = useCount
        }
        scheduleUseCountPersistence(id: id, useCount: useCount)
    }

    private func noteHistoryMutation() {
        historyRevision &+= 1
    }

    private func deleteImageFiles(for removedItems: [ClipboardItem]) {
        for item in removedItems where item.type == .image {
            let hasOtherReferences = historyIndex.hasOtherImageReferences(for: item.imageFileName)
            imageManager.deleteImageFile(for: item, hasOtherReferences: hasOtherReferences)
        }
    }

    private func persistItemIncrementally(_ item: ClipboardItem) {
        persistence.upsert(item)
    }

    private func persistDeletedIDsIncrementally(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        scheduleCloudDelete(ids: ids)
        persistence.delete(ids: ids)
    }

    private func scheduleUseCountPersistence(id: UUID, useCount: Int) {
        persistence.scheduleUseCount(id: id, useCount: useCount)
    }
    
    private func recomputePinnedCount() {
        cachedPinnedCount = items.reduce(0) { $0 + ($1.isPinned ? 1 : 0) }
    }
    
    init(
        storageDirectory: URL? = nil,
        startRuntimeServices: Bool = true,
        historyStore: ClipboardHistoryStore? = nil,
        imageStore: ClipboardImageStore? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        ocrService: OCRServiceProtocol? = nil
    ) {
        let resolvedStorageDirectory: URL
        if let storageDirectory {
            resolvedStorageDirectory = storageDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedStorageDirectory = appSupport.appendingPathComponent("ClipboardManager")
        }
        self.storageDirectory = resolvedStorageDirectory
        if let historyStore {
            self.historyStore = historyStore
        } else {
            let sqliteStore = SQLiteHistoryStore(storageDirectory: resolvedStorageDirectory)
            sqliteStore.migrateFromJSON(storageDirectory: resolvedStorageDirectory)
            self.historyStore = sqliteStore
        }
        let resolvedImageStore = imageStore ?? FileClipboardImageStore(storageDirectory: resolvedStorageDirectory)
        let resolvedPreferencesStore = preferencesStore ?? JSONAppPreferencesStore(storageDirectory: resolvedStorageDirectory)
        let resolvedOCR = ocrService ?? VisionOCRService.shared

        self.imageManager = ClipboardImageManager(imageStore: resolvedImageStore, ocrService: resolvedOCR)
        self.prefs = ClipboardPreferencesManager(preferencesStore: resolvedPreferencesStore)
        self.syncCoordinator = ClipboardSyncCoordinator(enableCloudSync: startRuntimeServices)
        CloudSyncService.shared.imageStore = resolvedImageStore

        self.monitor = ClipboardMonitor()
        self.persistence = ClipboardPersistenceCoordinator(
            historyStore: self.historyStore,
            logger: self.logger
        )
        self.ruleStore = JSONClipboardRuleStore(storageDirectory: resolvedStorageDirectory)
        
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        loadExcludedBundleIDs()
        loadRules()
        if let v = prefs.loadHotWindowCount() {
            hotWindowCount = Self.normalizedHotWindowCount(v)
        }
        loadItems()
        recomputePinnedCount()
        if imageManager.migrateLegacyInlineImages(items: &items) {
            rebuildItemIndexes()
            saveItems(immediately: true)
        }
        loadScalarPreferences()
        loadSmartPasteEnabled()
        cleanupOldItems()
        isInitializing = false
        configureOCRQueue()
        scheduleDeferredStartupMaintenance()
        configureCapturePipeline()
        configureRuntimeCallbacks(startRuntimeServices: startRuntimeServices)
        configureCloudDeleteObserver()
    }

    private func configureOCRQueue() {
        ocrQueue = ClipboardOCRQueue(
            imageManager: imageManager,
            itemProvider: { [weak self] id in
                self?.itemByID[id]
            },
            onRecognized: { [weak self] id, ocrText in
                guard let self else { return }
                guard let idx = self.indexForItem(id: id) else { return }
                self.items[idx].ocrText = ocrText
                self.updateIndexedItem(self.items[idx], at: idx)
                self.persistItemIncrementally(self.items[idx])
                self.scheduleCloudUpload(item: self.items[idx])
            }
        )
    }

    private func scheduleDeferredStartupMaintenance() {
        let orphanRefs = Set(items.compactMap(\.imageFileName))
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.imageManager.pruneOrphanedFiles(referencedFileNames: orphanRefs)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.migrateOCRForExistingImages()
        }
    }

    private func configureCapturePipeline() {
        captureDispatcher = ClipboardCaptureDispatcher(
            addText: { [weak self] content, sourceBundleID, sourceAppName, isSensitive, expiresAt, autoPin in
                guard let self else {
                    return ClipboardItem(content: content, type: .text)
                }
                return self.addTextItem(
                    content: content,
                    sourceBundleID: sourceBundleID,
                    sourceAppName: sourceAppName,
                    isSensitive: isSensitive,
                    expiresAt: expiresAt,
                    autoPin: autoPin
                )
            },
            addRichText: { [weak self] content, rtfData, sourceBundleID, sourceAppName, isSensitive, expiresAt, autoPin in
                guard let self else {
                    return ClipboardItem(content: content, rtfData: rtfData, type: .richText)
                }
                return self.addRichTextItem(
                    content: content,
                    rtfData: rtfData,
                    sourceBundleID: sourceBundleID,
                    sourceAppName: sourceAppName,
                    isSensitive: isSensitive,
                    expiresAt: expiresAt,
                    autoPin: autoPin
                )
            },
            addImage: { [weak self] imageData, sourceBundleID, sourceAppName, fileExtension, isScreenshot, completion in
                self?.prepareAndAddImageItem(
                    imageData: imageData,
                    sourceBundleID: sourceBundleID,
                    sourceAppName: sourceAppName,
                    fileExtension: fileExtension,
                    isScreenshot: isScreenshot,
                    completion: completion
                )
            },
            addFileURL: { [weak self] paths, sourceBundleID, sourceAppName, isSensitive, expiresAt, autoPin, isScreenshot in
                guard let self else {
                    return ClipboardItem(content: "", type: .fileURL)
                }
                return self.addFileURLItem(
                    paths: paths,
                    sourceBundleID: sourceBundleID,
                    sourceAppName: sourceAppName,
                    isSensitive: isSensitive,
                    expiresAt: expiresAt,
                    autoPin: autoPin,
                    isScreenshot: isScreenshot
                )
            }
        )
        ingestPipeline = ClipboardIngestPipeline(ruleEngine: ruleEngine) { [weak self] content, isSensitive, expiresAt, autoPin in
            self?.dispatchAdd(content, isSensitive: isSensitive, expiresAt: expiresAt, autoPin: autoPin)
        }
    }

    private func configureRuntimeCallbacks(startRuntimeServices: Bool) {
        monitor.excludedBundleIDs = cachedExcludedBundleIDs
        monitor.onCapture = { [weak self] content in
            self?.handleCapturedContent(content)
        }
        syncCoordinator.onItemsFetched = { [weak self] fetchedItems in
            self?.handleFetchedSyncItems(fetchedItems)
        }
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        if startRuntimeServices {
            monitor.start()
            configureCleanupTimer()
        }
    }

    private func configureCloudDeleteObserver() {
        cloudDeleteObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("ClipboardCloudDeleteItems"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let ids = notification.userInfo?["ids"] as? [UUID],
                      !ids.isEmpty else { return }
                let idSet = Set(ids)
                let removedItems = self.deleteItemsFromMemory(ids: idSet)
                self.deleteImageFiles(for: removedItems)
                self.saveItems(immediately: true)
                self.noteHistoryMutation()
            }
        }
    }
    
    deinit {
        monitor.stop()
        cleanupTimer?.invalidate()
        if let obs = cloudDeleteObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    // MARK: - Monitor Callback
    
    private func handleCapturedContent(_ content: CapturedContent) {
        ingestPipeline.handle(content)
    }
    
    private func dispatchAdd(_ content: CapturedContent, isSensitive: Bool = false, expiresAt: Date? = nil, autoPin: Bool = false) {
        captureDispatcher.dispatch(content, isSensitive: isSensitive, expiresAt: expiresAt, autoPin: autoPin)
    }
    
    private func configureCleanupTimer() {
        cleanupTimer?.invalidate()
        guard autoCleanupInterval > 0 else {
            cleanupTimer = nil
            return
        }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanupOldItems()
        }
    }
    
    // MARK: - Image Helpers (delegated to imageManager)
    
    func resolvedImage(for item: ClipboardItem) -> NSImage? {
        imageManager.resolvedImage(for: item)
    }

    func imageFileURL(for item: ClipboardItem) -> URL? {
        imageManager.imageFileURL(for: item)
    }
    
    // MARK: - Preferences (delegated to prefs)
    
    private func loadExcludedBundleIDs() {
        if let stored = prefs.loadExcludedBundleIDs() {
            cachedExcludedBundleIDs = stored
        }
    }
    
    private func loadScalarPreferences() {
        if let v = prefs.loadMaxHistoryCount() { maxHistoryCount = max(0, v) }
        if let v = prefs.loadAutoCleanupInterval() { autoCleanupInterval = max(0, v) }
        if let v = prefs.loadHotWindowCount() { hotWindowCount = Self.normalizedHotWindowCount(v) }
    }

    static func normalizedHotWindowCount(_ value: Int) -> Int {
        let allowed = [500, 1_000, 2_000, 5_000, 10_000]
        if allowed.contains(value) { return value }
        return Defaults.hotWindowCount
    }

    private func enforceHotWindowInMemory() {
        guard let enforced = ClipboardHistoryOrdering.enforceHotWindow(items, hotWindowCount: hotWindowCount) else {
            cachedPinnedCount = items.reduce(0) { $0 + ($1.isPinned ? 1 : 0) }
            return
        }
        items = enforced
        rebuildItemIndexes()
        recomputePinnedCount()
    }

    private func expandHotWindowIfNeeded() {
        do {
            let loaded = try historyStore.loadItems(limit: hotWindowCount)
            guard loaded.count > items.count else { return }
            let existing = Set(items.map(\.id))
            let missing = loaded.filter { !existing.contains($0.id) }
            guard !missing.isEmpty else { return }
            items = ClipboardHistoryOrdering.mergeMissingByPinAndTimestamp(existing: items, missing: missing)
            rebuildItemIndexes()
        } catch {
            logger.error("Failed to expand hot window: \(error.localizedDescription)")
        }
    }

    
    private func persistExcludedBundleIDs() {
        prefs.saveExcludedBundleIDs(cachedExcludedBundleIDs)
    }
    
    // MARK: - Add Items

    private func insertionIndexForNewItem(isPinned: Bool) -> Int {
        if isPinned { return 0 }
        return min(max(0, cachedPinnedCount), items.count)
    }

    @discardableResult
    private func insertNewHistoryItem(
        _ item: ClipboardItem,
        duplicateIDs: Set<UUID>,
        scheduleEmbedding: Bool = false,
        enqueueOCR: Bool = false
    ) -> ClipboardItem {
        let removedItems = deleteItemsFromMemory(ids: duplicateIDs)
        deleteImageFiles(for: removedItems)
        persistDeletedIDsIncrementally(duplicateIDs)
        if item.isPinned {
            cachedPinnedCount += 1
        }
        let insertAt = insertionIndexForNewItem(isPinned: item.isPinned)
        items.insert(item, at: insertAt)
        insertItemIntoIndexes(item, at: insertAt)
        SpotlightIndexService.shared.indexItem(item)
        if scheduleEmbedding {
            self.scheduleEmbedding(for: item)
        }
        trimToLimit()
        persistItemIncrementally(item)
        scheduleCloudUpload(item: item)
        if enqueueOCR {
            self.enqueueOCR(for: item.id)
        }
        totalStoredCount += 1
        noteHistoryMutation()
        return item
    }

    @discardableResult
    func addTextItem(content: String, sourceBundleID: String? = nil, sourceAppName: String? = nil, isSensitive: Bool = false, expiresAt: Date? = nil, autoPin: Bool = false) -> ClipboardItem {
        let duplicateIDs = historyIndex.unpinnedIDsByContentKey[ClipboardContentIndexKey(type: .text, content: content)] ?? []
        let item = ClipboardItem(content: content, type: .text, isPinned: autoPin, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName, isSensitive: isSensitive, expiresAt: expiresAt)
        return insertNewHistoryItem(item, duplicateIDs: duplicateIDs, scheduleEmbedding: true)
    }

    @discardableResult
    func addRichTextItem(content: String, rtfData: Data, sourceBundleID: String? = nil, sourceAppName: String? = nil, isSensitive: Bool = false, expiresAt: Date? = nil, autoPin: Bool = false) -> ClipboardItem {
        let duplicateIDs = historyIndex.unpinnedIDsByContentKey[ClipboardContentIndexKey(type: .richText, content: content)] ?? []
        let item = ClipboardItem(content: content, rtfData: rtfData, type: .richText, isPinned: autoPin, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName, isSensitive: isSensitive, expiresAt: expiresAt)
        return insertNewHistoryItem(item, duplicateIDs: duplicateIDs, scheduleEmbedding: true)
    }

    @discardableResult
    func addImageItem(imageData: Data, sourceBundleID: String? = nil, sourceAppName: String? = nil, fileExtension: String? = nil, isScreenshot: Bool = false) -> ClipboardItem {
        let hash = ClipboardItem.hash(for: imageData)
        let duplicateIDs = historyIndex.unpinnedImageIDsByHash[hash] ?? []
        let (storedFileName, inlineImageData) = imageManager.saveImageFile(imageData, fileExtension: fileExtension)
        let newItem = ClipboardItem(
            id: UUID(),
            imageData: inlineImageData,
            type: .image,
            imageHash: hash,
            imageFileName: storedFileName,
            sourceBundleID: sourceBundleID,
            sourceAppName: sourceAppName,
            isScreenshot: isScreenshot
        )
        return insertNewHistoryItem(newItem, duplicateIDs: duplicateIDs, enqueueOCR: true)
    }

    private func prepareAndAddImageItem(imageData: Data, sourceBundleID: String? = nil, sourceAppName: String? = nil, fileExtension: String? = nil, isScreenshot: Bool = false, completion: ((ClipboardItem) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let prepared = await self.imageManager.prepareImageFile(imageData, fileExtension: fileExtension)
            let item = self.insertPreparedImage(prepared, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName, isScreenshot: isScreenshot)
            if let item { completion?(item) }
        }
    }

    @discardableResult
    private func insertPreparedImage(_ prepared: PreparedClipboardImage, sourceBundleID: String? = nil, sourceAppName: String? = nil, isScreenshot: Bool = false) -> ClipboardItem? {
        let duplicateIDs = historyIndex.unpinnedImageIDsByHash[prepared.hash] ?? []
        let newItem = ClipboardItem(
            id: UUID(),
            imageData: prepared.inlineData,
            type: .image,
            imageHash: prepared.hash,
            imageFileName: prepared.fileName,
            sourceBundleID: sourceBundleID,
            sourceAppName: sourceAppName,
            isScreenshot: isScreenshot
        )
        return insertNewHistoryItem(newItem, duplicateIDs: duplicateIDs, enqueueOCR: true)
    }

    @discardableResult
    func addFileURLItem(paths: [String], sourceBundleID: String? = nil, sourceAppName: String? = nil,
                         isSensitive: Bool = false, expiresAt: Date? = nil, autoPin: Bool = false, isScreenshot: Bool = false) -> ClipboardItem {
        guard !paths.isEmpty else { return ClipboardItem(content: "", type: .fileURL) }
        let content = ClipboardContentCodec.encodeFilePaths(paths)
        let duplicateIDs = historyIndex.unpinnedIDsByContentKey[ClipboardContentIndexKey(type: .fileURL, content: content)] ?? []
        let item = ClipboardItem(content: content, type: .fileURL, isPinned: autoPin,
                                 sourceBundleID: sourceBundleID, sourceAppName: sourceAppName,
                                 isSensitive: isSensitive, expiresAt: expiresAt, isScreenshot: isScreenshot)
        return insertNewHistoryItem(item, duplicateIDs: duplicateIDs)
    }

    // MARK: - Actions
    
    func copyToClipboard(_ item: ClipboardItem, autoPaste: Bool = false, asPlainText: Bool = false) {
        let result = ClipboardPasteboardWriter.write(
            item: item,
            to: pasteboard,
            autoPaste: autoPaste,
            asPlainText: asPlainText,
            smartPasteEnabled: smartPasteEnabled,
            targetBundleID: targetBundleID,
            imagePayload: { [weak self] in
                self?.imageManager.pasteboardPayload(for: item)
            }
        )
        pasteboardDataProviders = result.retainedProviders
        if let description = result.smartPasteDescription {
            lastSmartPasteDescription = description
        }
        incrementUseCount(for: item.id)
        monitor.acknowledgeChangeCount()
        if autoPaste { onItemSelected?() }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        let removedItems = deleteItemsFromMemory(ids: [item.id])
        deleteImageFiles(for: removedItems)
        SpotlightIndexService.shared.deindexItem(id: item.id)
        persistDeletedIDsIncrementally([item.id])
        noteHistoryMutation()
    }
    
    func togglePin(_ item: ClipboardItem) {
        guard let index = indexForItem(id: item.id),
              let result = ClipboardHistoryOrdering.reorderedAfterTogglingPin(items: items, at: index) else {
            return
        }
        items = result.items
        cachedPinnedCount = result.pinnedCount
        rebuildItemIndexes()
        scheduleCloudUpload(item: result.updated)
        saveItems()
        noteHistoryMutation()
    }
    
    func clearAll() {
        let plan = ClipboardHistoryMaintenance.planClearUnpinned(items: items)
        guard !plan.removedIDs.isEmpty || totalStoredCount != plan.remainingItems.count else {
            cachedPinnedCount = plan.remainingItems.count
            return
        }
        deletedIDTombstones.formUnion(plan.removedIDs)
        items = plan.remainingItems
        rebuildItemIndexes()
        deleteImageFiles(for: plan.removedItems)
        do {
            let deleted = try historyStore.deleteUnpinned()
            totalStoredCount = items.count
            if deleted.isEmpty && !plan.removedIDs.isEmpty {
                persistDeletedIDsIncrementally(plan.removedIDs)
            } else if !deleted.isEmpty {
                scheduleCloudDelete(ids: deleted)
            }
        } catch {
            logger.error("Failed to clear unpinned history: \(error.localizedDescription)")
            if !plan.removedIDs.isEmpty {
                persistDeletedIDsIncrementally(plan.removedIDs)
            }
        }
        if !plan.removedItems.isEmpty || totalStoredCount != items.count {
            SpotlightIndexService.shared.deindexAll()
            if !items.isEmpty { SpotlightIndexService.shared.indexItems(items) }
        }
        cachedPinnedCount = items.count
        noteHistoryMutation()
    }
    
    @discardableResult
    func clearSensitiveItems() -> Int {
        let targets = ClipboardHistoryMaintenance.sensitiveItems(in: items)
        guard !targets.isEmpty else { return 0 }
        removeHistoryItems(targets, wipeFirst: true)
        return targets.count
    }
    
    func updateItemContent(_ item: ClipboardItem, newContent: String) {
        guard let index = indexForItem(id: item.id) else { return }
        items[index].content = newContent
        updateIndexedItem(items[index], at: index)
        persistItemIncrementally(items[index])
        scheduleCloudUpload(item: items[index])
    }
    
    // MARK: - Refresh
    
    /// Force an immediate clipboard check. Call when the panel is shown
    /// to ensure newly copied content appears without waiting for the next poll.
    func forceRefreshClipboard() {
        monitor.checkClipboard()
    }
    
    // MARK: - Search

    func search(_ query: String, limit: Int? = nil, where predicate: ((ClipboardItem) -> Bool)? = nil) -> [ClipboardItem] {
        let store = historyStore
        return ClipboardSearchService.search(
            query,
            limit: limit,
            where: predicate,
            context: ClipboardSearchService.Context(
                items: items,
                itemByID: itemByID,
                embeddingCache: embeddingCache,
                resolveMissing: { [weak self] id in
                    self?.resolveItemIncludingColdStorage(id: id)
                },
                searchFTS: { q, lim in store.searchFTS(q, limit: lim) }
            )
        )
    }

    // MARK: - AppIntents helpers

    /// Look up an item by its UUID without mutating state.
    func item(byID id: UUID) -> ClipboardItem? {
        if deletedIDTombstones.contains(id) { return nil }
        return itemByID[id]
    }

    private func resolveItemIncludingColdStorage(id: UUID) -> ClipboardItem? {
        if deletedIDTombstones.contains(id) { return nil }
        if let item = itemByID[id] { return item }
        guard let loaded = try? historyStore.loadItem(id: id) else { return nil }
        if deletedIDTombstones.contains(id) { return nil }
        historyIndex.setItem(loaded)
        return loaded
    }

    func item(at index: Int) -> ClipboardItem? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    func recentItemContents(limit: Int) -> [String] {
        ClipboardHistoryQueries.recentContents(from: items, limit: limit)
    }

    func itemContents(sourceBundleID: String, limit: Int) -> [String] {
        ClipboardHistoryQueries.contents(from: items, sourceBundleID: sourceBundleID, limit: limit)
    }

    func deleteItem(byID id: UUID) {
        guard let item = itemByID[id] else { return }
        deleteItem(item)
    }

    /// Toggle the pin state of an item by UUID.
    func pinItem(byID id: UUID) {
        guard let item = itemByID[id] else { return }
        togglePin(item)
    }
    
    // MARK: - Persistence

    /// Compute and persist an NLEmbedding vector for a newly added item, then update the in-memory cache.
    private func scheduleEmbedding(for item: ClipboardItem) {
        guard ClipboardEmbeddingPolicy.isEligible(item),
              SemanticSearchService.shared.isAvailable,
              let sqliteStore = historyStore as? SQLiteHistoryStore else { return }
        warmEmbeddings(for: [item], store: sqliteStore)
    }

    private func warmEmbeddings(for candidates: [ClipboardItem], store: SQLiteHistoryStore) {
        let cachedIDs = Set(embeddingCache.keys)
        SemanticSearchService.shared.scheduleEmbeddingBatch(
            for: candidates,
            store: store,
            cachedIDs: cachedIDs
        ) { [weak self] fresh in
            self?.embeddingCache.merge(fresh) { _, new in new }
        }
    }

    private func enqueueOCR(for id: UUID) {
        ocrQueue?.enqueue(id)
    }

    func flushPendingWrites() {
        applyPendingUseCountsToItems()
        persistence.flushAll(items: items)
    }

    func prepareForTermination() {
        flushPendingWrites()
        (historyStore as? SQLiteHistoryStore)?.optimizeForClose()
    }
    
    private func saveItems(immediately: Bool = false) {
        trimToLimit()
        applyPendingUseCountsToItems()
        persistence.scheduleSnapshot(items, immediately: immediately)
    }
    
    private func scheduleUsagePersist() {
        applyPendingUseCountsToItems()
        persistence.scheduleUsageSnapshot(items)
    }
    
    private func trimToLimit() {
        if maxHistoryCount > 0 {
            if let trimmed = ClipboardHistoryOrdering.trimUnpinnedInMemory(
                items,
                maxHistoryCount: maxHistoryCount,
                pinnedCount: cachedPinnedCount
            ) {
                let removedIDs = Set(trimmed.removed.map(\.id))
                items = trimmed.items
                removeIDsFromIndexes(removedIDs)
                deleteImageFiles(for: trimmed.removed)
                persistDeletedIDsIncrementally(removedIDs)
                recomputePinnedCount()
            }
            let maxUnpinned = ClipboardHistoryOrdering.maxUnpinnedCapacity(
                maxHistoryCount: maxHistoryCount,
                pinnedCount: cachedPinnedCount,
                itemCount: items.count
            )
            do {
                let coldRemoved = try historyStore.trimUnpinned(to: maxUnpinned)
                if !coldRemoved.isEmpty {
                    totalStoredCount = max(0, totalStoredCount - coldRemoved.count)
                }
            } catch {
                logger.error("Failed to trim cold history: \(error.localizedDescription)")
            }
        }
        enforceHotWindowInMemory()
    }
    
    private func loadItems() {
        do {
            totalStoredCount = (try? historyStore.itemCount()) ?? 0
            items = try historyStore.loadItems(limit: hotWindowCount)
            rebuildItemIndexes()
            noteHistoryMutation()
            warmLoadedEmbeddingsIfNeeded()
        }
        catch { logger.error("Failed to load clipboard history: \(error.localizedDescription)") }
    }

    private func warmLoadedEmbeddingsIfNeeded() {
        guard let sqliteStore = historyStore as? SQLiteHistoryStore else { return }
        embeddingCache = sqliteStore.loadEmbeddings(limit: ClipboardEmbeddingPolicy.startupWarmLimit)
        let candidates = ClipboardEmbeddingPolicy.startupWarmItems(from: items)
        warmEmbeddings(for: candidates, store: sqliteStore)
    }
    
    
    private func migrateOCRForExistingImages() {
        let candidateIDs = ClipboardHistoryMaintenance.ocrMigrationCandidateIDs(
            in: items,
            limit: startupOCRMigrationLimit
        )
        for id in candidateIDs {
            enqueueOCR(for: id)
        }
    }
    
    func cleanupOldItems() {
        let now = Date()
        var accountedIDs = Set<UUID>()
        let expired = ClipboardHistoryMaintenance.expiredItems(in: items, now: now)
        if !expired.isEmpty {
            removeHistoryItems(expired, wipeFirst: true)
            accountedIDs.formUnion(expired.map(\.id))
        }
        do {
            let coldExpired = try historyStore.deleteExpired(before: now)
            let additional = ClipboardHistoryMaintenance.additionalStoreIDs(coldExpired, excluding: accountedIDs)
            if !additional.isEmpty {
                deletedIDTombstones.formUnion(additional)
                totalStoredCount = max(0, totalStoredCount - additional.count)
                scheduleCloudDelete(ids: additional)
            }
        } catch {
            logger.error("Failed to delete expired cold items: \(error.localizedDescription)")
        }

        if let cutoffDate = ClipboardHistoryMaintenance.autoCleanupCutoff(intervalDays: autoCleanupInterval, now: now) {
            let old = ClipboardHistoryMaintenance.autoCleanupCandidates(in: items, olderThan: cutoffDate)
            if !old.isEmpty {
                removeHistoryItems(old)
                accountedIDs.formUnion(old.map(\.id))
            }
            do {
                let coldOld = try historyStore.deleteUnpinnedOlderThan(cutoffDate)
                let additional = ClipboardHistoryMaintenance.additionalStoreIDs(coldOld, excluding: accountedIDs)
                if !additional.isEmpty {
                    deletedIDTombstones.formUnion(additional)
                    totalStoredCount = max(0, totalStoredCount - additional.count)
                    scheduleCloudDelete(ids: additional)
                }
            } catch {
                logger.error("Failed to delete old cold items: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Smart Paste
    
    private func loadSmartPasteEnabled() {
        if let v = prefs.loadSmartPasteEnabled() { smartPasteEnabled = v }
    }
    
    // MARK: - Cloud Sync (delegated to syncCoordinator)
    
    private func handleFetchedSyncItems(_ fetchedItems: [ClipboardItem]) {
        let newItems = fetchedItems.filter { itemByID[$0.id] == nil }
        guard !newItems.isEmpty else { return }
        mergeFetchedSyncItems(newItems)
        recomputePinnedCount()
        rebuildItemIndexes()
        saveItems()
    }

    func mergeFetchedSyncItems(_ newItems: [ClipboardItem]) {
        guard !newItems.isEmpty else { return }
        items = ClipboardHistoryOrdering.mergeFetched(
            existing: items,
            pinnedCount: cachedPinnedCount,
            incoming: newItems
        )
        totalStoredCount += newItems.count
        noteHistoryMutation()
    }

    private func scheduleCloudUpload(item: ClipboardItem) {
        syncCoordinator.scheduleUpload(item: item)
    }

    private func scheduleCloudDelete(ids: Set<UUID>) {
        syncCoordinator.scheduleDeletes(ids: ids)
    }
    
    // MARK: - Rules
    
    private func loadRules() {
        do { ruleEngine.rules = try ruleStore.loadRules() }
        catch { logger.error("Failed to load rules: \(error.localizedDescription)") }
    }
    
    func saveRules() {
        do { try ruleStore.saveRules(ruleEngine.rules) }
        catch { logger.error("Failed to save rules: \(error.localizedDescription)") }
    }
}
