import XCTest
@testable import ClipShelf

final class PerformanceBenchmarkTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { i in
            ClipboardItem(
                content: "item \(i) keyword benchmark text variant \(i % 100)",
                type: .text,
                sourceAppName: i.isMultiple(of: 2) ? "Safari" : "Notes"
            )
        }
    }

    /// Creates and populates a fresh SQLiteHistoryStore in its own subdirectory.
    private func populatedStore(count: Int) throws -> SQLiteHistoryStore {
        let dir = tempDir.appendingPathComponent("store-\(count)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SQLiteHistoryStore(storageDirectory: dir)
        try store.saveItems(makeItems(count: count))
        return store
    }

    private func makeDataPortService() -> DataPortService {
        DataPortService(
            storageDirectory: tempDir,
            historyStore: InMemoryClipboardHistoryStore(),
            imageStore: InMemoryClipboardImageStore()
        )
    }

    private func makePNGData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: - FTS Benchmarks

    func testFTSSearchPerformance_1k() throws {
        let store = try populatedStore(count: 1_000)
        measure {
            _ = store.searchFTS("keyword")
        }
    }

    func testFTSSearchPerformance_10k() throws {
        let store = try populatedStore(count: 10_000)
        measure {
            _ = store.searchFTS("keyword")
        }
    }

    func testFTSSearchHonorsLimit() throws {
        let store = try populatedStore(count: 1_000)
        let results = store.searchFTS("keyword", limit: 200)
        XCTAssertEqual(results.count, 200)
    }

    // MARK: - Fuzzy Search Fallback Benchmarks (comparison baseline)

    func testFuzzySearchFallback_1k() {
        let items = makeItems(count: 1_000)
        measure {
            _ = FuzzySearch.search("keyword", in: items)
        }
    }

    func testFuzzySearchLimitPerformance_50k() {
        let items = makeItems(count: 50_000)
        measure {
            let results = FuzzySearch.search("keyword", in: items, limit: 200)
            XCTAssertLessThanOrEqual(results.count, 200)
        }
    }

    func testFuzzySearchPredicateLimitDoesNotMaterializeAllCandidates_50k() {
        let items = makeItems(count: 50_000)
        var predicateCalls = 0

        let results = FuzzySearch.search("", in: items, limit: 200) { item in
            predicateCalls += 1
            return item.type == .text
        }

        XCTAssertEqual(results.count, 200)
        XCTAssertEqual(predicateCalls, 200)
    }

    func testListPaginatorStopsAfterVisiblePage_50k() {
        let items = makeItems(count: 50_000)
        var evaluated = 0

        let page = ClipboardListPaginator.page(from: items, visibleCount: 200) { item in
            evaluated += 1
            return item.type == .text
        }

        XCTAssertEqual(page.items.count, 200)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(evaluated, 201)
    }

    // MARK: - ClipboardManager Hot Path Benchmarks

    @MainActor
    func testManagerAddTextDedupPerformance_50k() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        historyStore.seed(makeItems(count: 50_000))
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )

        measure {
            manager.addTextItem(content: "item 49999 keyword benchmark text variant 99")
        }
        XCTAssertLessThanOrEqual(manager.items.count, 2_001)
    }

    @MainActor
    func testManagerCopyUseCountPerformance_50k() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        historyStore.seed(makeItems(count: 50_000))
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )
        let target = manager.items.last!

        measure {
            manager.copyToClipboard(target)
        }
        XCTAssertGreaterThan(manager.item(byID: target.id)?.useCount ?? 0, 0)
    }

    @MainActor
    func testManagerCopyAfterHeadInsertPerformance_50k() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        historyStore.seed(makeItems(count: 50_000))
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )
        XCTAssertLessThanOrEqual(manager.items.count, 2_000)
        let target = manager.items[min(10, max(0, manager.items.count - 1))]
        manager.addTextItem(content: "fresh head insert")

        measure {
            manager.copyToClipboard(target)
        }
        XCTAssertGreaterThan(manager.item(byID: target.id)?.useCount ?? 0, 0)
    }

    @MainActor
    func testManagerAddImageDedupPerformance_20k() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        let duplicateData = Data(repeating: 0x7B, count: 1024)
        let duplicateHash = ClipboardItem.hash(for: duplicateData)
        historyStore.seed((0..<20_000).map { i in
            ClipboardItem(
                type: .image,
                imageHash: i == 100 ? duplicateHash : "hash-\(i)",
                imageFileName: "image-\(i).png"
            )
        })
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )

        measure {
            manager.addImageItem(imageData: duplicateData)
        }
        XCTAssertEqual(manager.items.filter { $0.imageHash == duplicateHash }.count, 1)
    }

    @MainActor
    func testManagerMergeFetchedSyncItemsPerformance_50kSmallBatch() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        let now = Date()
        historyStore.seed((0..<50_000).map { i in
            ClipboardItem(
                content: "local \(i)",
                type: .text,
                timestamp: now.addingTimeInterval(-Double(i + 10))
            )
        })
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )
        let incoming = (0..<20).map { i in
            ClipboardItem(
                content: "remote \(i)",
                type: .text,
                timestamp: now.addingTimeInterval(-Double(i))
            )
        }

        measure {
            manager.items = historyStore.items
            manager.mergeFetchedSyncItems(incoming)
        }

        XCTAssertEqual(manager.items.prefix(20).map(\.content), incoming.map(\.content))
    }

    @MainActor
    func testManagerAddImagePreservesKnownExtension() {
        let historyStore = InMemoryClipboardHistoryStore()
        let imageStore = InMemoryClipboardImageStore()
        let prefsStore = InMemoryAppPreferencesStore()
        prefsStore.maxHistoryCount = 0
        let manager = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: InMemoryOCRService()
        )
        let data = Data(repeating: 0x4A, count: 1024)

        manager.addImageItem(imageData: data, fileExtension: "jpg")

        XCTAssertEqual(manager.items.first?.imageFileName?.hasSuffix(".jpg"), true)
        XCTAssertEqual(imageStore.storage.values.first, data)
    }

    @MainActor
    func testPrepareImageFileProducesHashAndStoredFile() async {
        let imageStore = InMemoryClipboardImageStore()
        let manager = ClipboardImageManager(imageStore: imageStore, ocrService: InMemoryOCRService())
        let data = Data(repeating: 0x5A, count: 1024)

        let prepared = await manager.prepareImageFile(data, fileExtension: "png")

        XCTAssertEqual(prepared.hash, ClipboardItem.hash(for: data))
        XCTAssertEqual(prepared.fileName?.hasSuffix(".png"), true)
        XCTAssertNil(prepared.inlineData)
        XCTAssertEqual(imageStore.storage[prepared.fileName ?? ""], data)
    }

    @MainActor
    func testFileImagePasteboardPayloadUsesLazyProvider() throws {
        let imageStore = FileClipboardImageStore(storageDirectory: tempDir)
        let manager = ClipboardImageManager(imageStore: imageStore, ocrService: InMemoryOCRService())
        let data = Data(repeating: 0x6B, count: 1024 * 1024)
        let fileName = "large-pasteboard.png"
        try imageStore.saveImageData(data, fileName: fileName)
        ImageCache.shared.clearAll()
        let item = ClipboardItem(type: .image, imageHash: ClipboardItem.hash(for: data), imageFileName: fileName)

        let payload = manager.pasteboardPayload(for: item)

        XCTAssertNil(payload?.data)
        XCTAssertNotNil(payload?.dataProvider)
        XCTAssertEqual(payload?.type, .png)
    }

    @MainActor
    func testLazyPasteboardProviderLoadsImageDataOnDemand() throws {
        let imageStore = FileClipboardImageStore(storageDirectory: tempDir)
        let data = Data(repeating: 0x7C, count: 1024)
        let fileName = "provider-demand.png"
        try imageStore.saveImageData(data, fileName: fileName)
        ImageCache.shared.clearAll()
        let provider = ClipboardImagePasteboardDataProvider(fileName: fileName, fileURL: imageStore.fileURL(for: fileName))
        let item = NSPasteboardItem()

        provider.pasteboard(nil, item: item, provideDataForType: .png)

        XCTAssertEqual(item.data(forType: .png), data)
    }

    func testImageThumbnailCacheDoesNotPopulateFullImageCache() {
        let imageData = makePNGData(width: 512, height: 512)
        let fileName = "large.png"
        ImageCache.shared.clearAll()

        let thumb = ImageCache.shared.thumbnail(for: fileName, maxPixelSize: 80) {
            imageData
        }

        XCTAssertNotNil(thumb)
        XCTAssertNil(ImageCache.shared.cachedSharedImage(for: fileName))
    }

    func testImageThumbnailDiskCacheAvoidsReloadingOriginalImage() {
        let imageData = makePNGData(width: 512, height: 512)
        let fileName = "disk-large.png"
        let cacheDir = tempDir.appendingPathComponent("thumbs", isDirectory: true)
        ImageCache.shared.clearAll()
        ImageCache.shared.configureThumbnailDiskCache(directory: cacheDir)

        let first = ImageCache.shared.thumbnailData(for: fileName, maxPixelSize: 80) {
            imageData
        }

        ImageCache.shared.clearAll()
        var loaderCalls = 0
        let second = ImageCache.shared.thumbnailData(for: fileName, maxPixelSize: 80) {
            loaderCalls += 1
            return nil
        }

        XCTAssertNotNil(first)
        XCTAssertEqual(second, first)
        XCTAssertEqual(loaderCalls, 0)
    }

    @MainActor
    func testRuleEngineCachedPlanPerformance_200Rules() async {
        let engine = ClipboardRuleEngine()
        engine.rules = (0..<200).map { index in
            ClipboardRule(
                name: "rule-\(index)",
                isEnabled: true,
                trigger: .contentMatches(pattern: "keyword"),
                actions: [.autoPin],
                order: index
            )
        }
        let content = CapturedContent(kind: .text(content: "keyword text"), sourceBundleID: nil, sourceAppName: nil)

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 {
            _ = await engine.process(content)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.3)
    }

    // MARK: - Export Benchmarks

    func testCSVExportPerformance_1k() {
        let items = makeItems(count: 1_000)
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("bench.csv")
        measure {
            try? service.exportCSV(to: destURL, items: items)
        }
    }

    func testMarkdownExportPerformance_1k() {
        let items = makeItems(count: 1_000)
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("bench.md")
        measure {
            try? service.exportMarkdown(to: destURL, items: items)
        }
    }

    // MARK: - FTS Unit Tests

    func testFTSMigrationProducesResults() throws {
        let store = SQLiteHistoryStore(storageDirectory: tempDir)
        let targetItem = ClipboardItem(content: "unique token benchmark content", type: .text)
        let otherItems = (0..<50).map { ClipboardItem(content: "unrelated item \($0)", type: .text) }
        try store.saveItems([targetItem] + otherItems)

        let results = store.searchFTS("unique token")
        XCTAssertFalse(results.isEmpty, "FTS search should return results for a known token")
        XCTAssertTrue(results.contains(targetItem.id), "FTS search should include the target item's UUID")
    }

    func testFTSEmptyQueryReturnsEmpty() throws {
        let store = SQLiteHistoryStore(storageDirectory: tempDir)
        try store.saveItems([ClipboardItem(content: "hello world", type: .text)])
        XCTAssertTrue(store.searchFTS("").isEmpty, "Empty query should return empty array")
    }

    func testFTSReservedWordsOnlyReturnsEmpty() throws {
        let store = SQLiteHistoryStore(storageDirectory: tempDir)
        try store.saveItems([ClipboardItem(content: "AND OR NOT", type: .text)])
        XCTAssertTrue(store.searchFTS("AND OR NOT").isEmpty, "FTS reserved words only → empty (filtered out)")
    }

    func testFTSSanitizesMetacharacters() throws {
        let store = SQLiteHistoryStore(storageDirectory: tempDir)
        try store.saveItems([ClipboardItem(content: "safe content", type: .text)])
        // These must not crash or throw
        _ = store.searchFTS("query:*-(unsafe)^")
        _ = store.searchFTS("\"quoted\" OR (AND)")
    }

    // MARK: - CSV Export Unit Tests

    func testCSVExportHeaderAndRowCount() throws {
        let items = makeItems(count: 5)
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("test.csv")
        try service.exportCSV(to: destURL, items: items)

        let csv = try String(contentsOf: destURL, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6, "CSV should have 1 header + 5 data rows")
        XCTAssertEqual(lines[0], "timestamp,type,content,source_app,is_pinned,ocr_text")
    }

    func testCSVExportEscapesSpecialCharacters() throws {
        let items = [
            ClipboardItem(content: "value,with,commas", type: .text),
            ClipboardItem(content: "value \"quoted\"", type: .text),
        ]
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("special.csv")
        try service.exportCSV(to: destURL, items: items)

        let csv = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("\"value,with,commas\""), "Comma-containing field must be quoted")
        XCTAssertTrue(csv.contains("\"value \"\"quoted\"\"\""), "Double-quoted field must use RFC 4180 escaping")
    }

    func testCSVExportPinnedFlagIsCorrect() throws {
        let pinned    = ClipboardItem(content: "pinned item", type: .text, isPinned: true)
        let unpinned  = ClipboardItem(content: "unpinned item", type: .text, isPinned: false)
        let service   = makeDataPortService()
        let destURL   = tempDir.appendingPathComponent("pinned.csv")
        try service.exportCSV(to: destURL, items: [pinned, unpinned])

        let csv = try String(contentsOf: destURL, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        // is_pinned is the 5th column (0-indexed: 4); trailing comma from empty ocr_text
        XCTAssertTrue(lines[1].contains(",1,"), "Pinned row should have is_pinned=1")
        XCTAssertTrue(lines[2].contains(",0,"), "Unpinned row should have is_pinned=0")
    }

    // MARK: - Markdown Export Unit Tests

    func testMarkdownExportContainsTableHeader() throws {
        let items = makeItems(count: 3)
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("test.md")
        try service.exportMarkdown(to: destURL, items: items)

        let md = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertTrue(md.hasPrefix("# Clipboard History"), "Markdown must start with h1 heading")
        XCTAssertTrue(md.contains("| # | Time | Type | Content | App | Pinned |"), "Must include table header row")
        XCTAssertTrue(md.contains("|---|"), "Must include table separator row")
    }

    func testMarkdownExportRowCountMatchesItems() throws {
        let count = 7
        let items = makeItems(count: count)
        let service = makeDataPortService()
        let destURL = tempDir.appendingPathComponent("rows.md")
        try service.exportMarkdown(to: destURL, items: items)

        let md = try String(contentsOf: destURL, encoding: .utf8)
        let dataRows = md.components(separatedBy: "\n").filter { $0.hasPrefix("| ") && !$0.hasPrefix("| #") && !$0.hasPrefix("|---") }
        XCTAssertEqual(dataRows.count, count, "Markdown should contain one data row per item")
    }

    // MARK: - Maccy Import Unit Tests

    func testMaccyImportRejectsNonMaccyDatabase() throws {
        // Write a plain text file — not a valid Maccy CoreData SQLite DB
        let invalidDBURL = tempDir.appendingPathComponent("invalid.sqlite")
        try "not a sqlite database".write(to: invalidDBURL, atomically: true, encoding: .utf8)

        let service = makeDataPortService()
        XCTAssertThrowsError(
            try service.importMaccy(from: invalidDBURL, existingItems: [], mode: .replace)
        ) { error in
            XCTAssertTrue(error is DataPortError, "Should throw DataPortError, got \(type(of: error))")
        }
    }

    func testAlfredImportRejectsNonAlfredDatabase() throws {
        let invalidDBURL = tempDir.appendingPathComponent("invalid_alfred.sqlite")
        try "not a sqlite database".write(to: invalidDBURL, atomically: true, encoding: .utf8)

        let service = makeDataPortService()
        XCTAssertThrowsError(
            try service.importAlfred(from: invalidDBURL, existingItems: [], mode: .replace)
        ) { error in
            XCTAssertTrue(error is DataPortError, "Should throw DataPortError, got \(type(of: error))")
        }
    }
}
