import XCTest
@testable import ClipShelf

@MainActor
final class ClipboardManagerTests: XCTestCase {

    private var historyStore: InMemoryClipboardHistoryStore!
    private var imageStore: InMemoryClipboardImageStore!
    private var prefsStore: InMemoryAppPreferencesStore!
    private var ocrService: InMemoryOCRService!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        historyStore = InMemoryClipboardHistoryStore()
        imageStore = InMemoryClipboardImageStore()
        prefsStore = InMemoryAppPreferencesStore()
        ocrService = InMemoryOCRService()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeManager() -> ClipboardManager {
        ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: historyStore,
            imageStore: imageStore,
            preferencesStore: prefsStore,
            ocrService: ocrService
        )
    }

    private func waitForOCRCompletions(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if ocrService.completions.count >= count { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for OCR completion", file: file, line: line)
    }

    // MARK: - addTextItem

    func testAddTextItem() {
        let mgr = makeManager()
        mgr.addTextItem(content: "hello")
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items.first?.content, "hello")
        XCTAssertEqual(mgr.items.first?.type, .text)
    }

    func testAddTextItemDedup() {
        let mgr = makeManager()
        mgr.addTextItem(content: "hello")
        mgr.addTextItem(content: "hello")
        XCTAssertEqual(mgr.items.count, 1, "Duplicate text should be deduplicated")
    }

    func testAddTextItemPinnedNotDeduped() {
        let mgr = makeManager()
        mgr.addTextItem(content: "hello")
        mgr.togglePin(mgr.items[0])
        mgr.addTextItem(content: "hello")
        XCTAssertEqual(mgr.items.count, 2, "Pinned item should not be removed by dedup")
        XCTAssertTrue(mgr.items[0].isPinned)
    }

    func testCopyAfterMultipleHeadInsertsUpdatesOriginalItem() {
        historyStore.seed([
            ClipboardItem(content: "old 0", type: .text),
            ClipboardItem(content: "old 1", type: .text),
            ClipboardItem(content: "old 2", type: .text)
        ])
        let mgr = makeManager()
        let target = mgr.items[2]

        for value in 0..<10 {
            mgr.addTextItem(content: "fresh \(value)")
        }

        mgr.copyToClipboard(target)

        XCTAssertEqual(mgr.item(byID: target.id)?.useCount, 1)
    }

    func testDeleteAfterMultipleHeadInsertsRemovesOriginalItem() {
        historyStore.seed([
            ClipboardItem(content: "old 0", type: .text),
            ClipboardItem(content: "old 1", type: .text),
            ClipboardItem(content: "old 2", type: .text)
        ])
        let mgr = makeManager()
        let target = mgr.items[1]

        for value in 0..<10 {
            mgr.addTextItem(content: "fresh \(value)")
        }

        mgr.deleteItem(target)

        XCTAssertNil(mgr.item(byID: target.id))
        XCTAssertFalse(mgr.items.contains { $0.id == target.id })
    }

    func testDedupAfterMultipleHeadInsertsRemovesOriginalItem() {
        historyStore.seed([
            ClipboardItem(content: "duplicate", type: .text),
            ClipboardItem(content: "old 1", type: .text),
            ClipboardItem(content: "old 2", type: .text)
        ])
        let mgr = makeManager()
        let originalID = mgr.items[0].id

        for value in 0..<10 {
            mgr.addTextItem(content: "fresh \(value)")
        }
        mgr.addTextItem(content: "duplicate")

        XCTAssertNil(mgr.item(byID: originalID))
        XCTAssertEqual(mgr.items.filter { $0.content == "duplicate" }.count, 1)
        XCTAssertEqual(mgr.items.first?.content, "duplicate")
    }

    // MARK: - addRichTextItem

    func testAddRichTextItem() {
        let mgr = makeManager()
        let rtf = "rtf data".data(using: .utf8)!
        mgr.addRichTextItem(content: "styled", rtfData: rtf)
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items.first?.type, .richText)
        XCTAssertEqual(mgr.items.first?.rtfData, rtf)
    }

    func testAddRichTextItemDedup() {
        let mgr = makeManager()
        let rtf1 = "v1".data(using: .utf8)!
        let rtf2 = "v2".data(using: .utf8)!
        mgr.addRichTextItem(content: "text", rtfData: rtf1)
        mgr.addRichTextItem(content: "text", rtfData: rtf2)
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items.first?.rtfData, rtf2, "Newer RTF data should replace older")
    }

    // MARK: - addImageItem

    func testAddImageItem() {
        let mgr = makeManager()
        let data = Data(repeating: 0xAB, count: 64)
        mgr.addImageItem(imageData: data)
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items.first?.type, .image)
        XCTAssertNotNil(mgr.items.first?.imageHash)
        XCTAssertNotNil(mgr.items.first?.imageFileName)
        XCTAssertEqual(imageStore.storage.count, 1)
    }

    func testAddImageItemDedup() {
        let mgr = makeManager()
        let data = Data(repeating: 0xCD, count: 64)
        mgr.addImageItem(imageData: data)
        mgr.addImageItem(imageData: data)
        XCTAssertEqual(mgr.items.count, 1, "Same image hash should be deduplicated")
    }

    func testOCRQueueDepthIsBoundedForImageBursts() {
        ocrService.holdCompletions = true
        let mgr = makeManager()

        for value in 0..<100 {
            mgr.addImageItem(imageData: Data(repeating: UInt8(value), count: 64))
        }

        XCTAssertLessThanOrEqual(mgr.pendingOCRQueueDepth, 64)
        ocrService.completeAll()
    }

    func testDeletingQueuedOCRItemDoesNotSkipNextQueuedItem() async {
        ocrService.holdCompletions = true
        ocrService.resultToReturn = "recognized"
        let mgr = makeManager()

        mgr.addImageItem(imageData: Data(repeating: 1, count: 64))
        mgr.addImageItem(imageData: Data(repeating: 2, count: 64))
        mgr.addImageItem(imageData: Data(repeating: 3, count: 64))
        let queuedToDelete = mgr.items[1]
        let nextQueued = mgr.items[0]

        await waitForOCRCompletions(1)
        mgr.deleteItem(queuedToDelete)
        ocrService.completeNext()
        await waitForOCRCompletions(1)
        ocrService.completeNext()

        XCTAssertEqual(mgr.item(byID: nextQueued.id)?.ocrText, "recognized")
    }

    // MARK: - togglePin

    func testTogglePin() {
        let mgr = makeManager()
        mgr.addTextItem(content: "a")
        mgr.addTextItem(content: "b")
        let itemB = mgr.items.first!  // "b" is newest, at top
        mgr.togglePin(itemB)
        XCTAssertTrue(mgr.items[0].isPinned, "Pinned item should be at top")
        XCTAssertEqual(mgr.items[0].content, "b")
    }

    func testUnpin() {
        let mgr = makeManager()
        mgr.addTextItem(content: "a")
        mgr.togglePin(mgr.items[0])
        XCTAssertTrue(mgr.items[0].isPinned)
        mgr.togglePin(mgr.items[0])
        XCTAssertFalse(mgr.items[0].isPinned)
    }

    // MARK: - deleteItem

    func testDeleteItem() {
        let mgr = makeManager()
        mgr.addTextItem(content: "hello")
        let item = mgr.items[0]
        mgr.deleteItem(item)
        XCTAssertTrue(mgr.items.isEmpty)
    }

    func testDeleteImageItemCleansUpFile() {
        let mgr = makeManager()
        let data = Data(repeating: 0xEF, count: 64)
        mgr.addImageItem(imageData: data)
        let item = mgr.items[0]
        let fileName = item.imageFileName!
        mgr.deleteItem(item)
        XCTAssertTrue(mgr.items.isEmpty)
        XCTAssertTrue(imageStore.deletedFileNames.contains(fileName))
    }

    // MARK: - clearAll

    func testClearAllKeepsPinned() {
        let mgr = makeManager()
        mgr.addTextItem(content: "keep")
        mgr.addTextItem(content: "remove")
        mgr.togglePin(mgr.items.first(where: { $0.content == "keep" })!)
        mgr.clearAll()
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items[0].content, "keep")
        XCTAssertTrue(mgr.items[0].isPinned)
    }

    func testClearAllEmpty() {
        let mgr = makeManager()
        mgr.clearAll()
        XCTAssertTrue(mgr.items.isEmpty)
    }

    // MARK: - trimToLimit

    func testTrimToLimit() {
        prefsStore.maxHistoryCount = 3
        let mgr = makeManager()
        for i in 1...5 {
            mgr.addTextItem(content: "item \(i)")
        }
        XCTAssertEqual(mgr.items.count, 3)
        // Newest items should survive
        XCTAssertEqual(mgr.items[0].content, "item 5")
        XCTAssertEqual(mgr.items[2].content, "item 3")
    }

    func testTrimToLimitPreservesPinned() {
        prefsStore.maxHistoryCount = 2
        let mgr = makeManager()
        mgr.addTextItem(content: "old")
        mgr.togglePin(mgr.items[0])
        mgr.addTextItem(content: "mid")
        mgr.addTextItem(content: "new")
        // pinned "old" + 1 unpinned = 2 total
        XCTAssertEqual(mgr.items.count, 2)
        XCTAssertTrue(mgr.items[0].isPinned)
        XCTAssertEqual(mgr.items[1].content, "new")
    }

    // MARK: - cleanupOldItems

    func testCleanupOldItems() {
        let mgr = makeManager()
        // Insert an item with old timestamp
        let oldItem = ClipboardItem(content: "old", type: .text, timestamp: Date().addingTimeInterval(-8 * 86400))
        let newItem = ClipboardItem(content: "new", type: .text)
        mgr.items = [newItem, oldItem]
        mgr.autoCleanupInterval = 7  // 7 days
        mgr.cleanupOldItems()
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items[0].content, "new")
    }

    func testCleanupOldItemsSkipsPinned() {
        let mgr = makeManager()
        let oldPinned = ClipboardItem(content: "pinned", type: .text, timestamp: Date().addingTimeInterval(-30 * 86400), isPinned: true)
        mgr.items = [oldPinned]
        mgr.autoCleanupInterval = 7
        mgr.cleanupOldItems()
        XCTAssertEqual(mgr.items.count, 1)
    }

    func testMergeFetchedSyncItemsPreservesPinnedAndTimestampOrder() {
        let now = Date()
        historyStore.seed([
            ClipboardItem(content: "pinned old", type: .text, timestamp: now.addingTimeInterval(-30), isPinned: true),
            ClipboardItem(content: "unpinned newest", type: .text, timestamp: now.addingTimeInterval(-10)),
            ClipboardItem(content: "unpinned old", type: .text, timestamp: now.addingTimeInterval(-40))
        ])
        let mgr = makeManager()

        mgr.mergeFetchedSyncItems([
            ClipboardItem(content: "pinned new", type: .text, timestamp: now.addingTimeInterval(-5), isPinned: true),
            ClipboardItem(content: "unpinned middle", type: .text, timestamp: now.addingTimeInterval(-20))
        ])

        XCTAssertEqual(mgr.items.map(\.content), [
            "pinned new",
            "pinned old",
            "unpinned newest",
            "unpinned middle",
            "unpinned old"
        ])
    }

    // MARK: - search

    func testSearchSingleKeyword() {
        let mgr = makeManager()
        mgr.addTextItem(content: "Hello World")
        mgr.addTextItem(content: "Goodbye")
        let results = mgr.search("hello")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "Hello World")
    }

    func testSearchMultipleKeywords() {
        let mgr = makeManager()
        mgr.addTextItem(content: "Swift programming language")
        mgr.addTextItem(content: "Swift bird")
        let results = mgr.search("swift programming")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].content.contains("programming"))
    }

    func testSearchEmptyQuery() {
        let mgr = makeManager()
        mgr.addTextItem(content: "hello")
        let results = mgr.search("")
        XCTAssertEqual(results.count, mgr.items.count)
    }

    func testSearchCaseInsensitive() {
        let mgr = makeManager()
        mgr.addTextItem(content: "UPPERCASE text")
        let results = mgr.search("uppercase")
        XCTAssertEqual(results.count, 1)
    }

    func testRecentAndSourceLimitedContentHelpers() {
        let mgr = makeManager()
        mgr.addTextItem(content: "notes old", sourceBundleID: "com.apple.Notes")
        mgr.addTextItem(content: "safari", sourceBundleID: "com.apple.Safari")
        mgr.addTextItem(content: "notes new", sourceBundleID: "com.apple.Notes")

        XCTAssertEqual(mgr.recentItemContents(limit: 2), ["notes new", "safari"])
        XCTAssertEqual(mgr.itemContents(sourceBundleID: "com.apple.Notes", limit: 1), ["notes new"])
        XCTAssertEqual(mgr.item(at: 1)?.content, "safari")
    }

    func testFileURLItemParsesPaths() {
        let paths = ["/tmp/a.txt", "/tmp/b.txt"]
        let item = ClipboardItem(
            content: String(data: try! JSONEncoder().encode(paths), encoding: .utf8)!,
            type: .fileURL
        )
        XCTAssertEqual(item.filePaths, paths)
    }

    // MARK: - copyToClipboard useCount

    func testCopyToClipboardIncrementsUseCount() {
        let mgr = makeManager()
        mgr.addTextItem(content: "test")
        XCTAssertEqual(mgr.items[0].useCount, 0)
        mgr.copyToClipboard(mgr.items[0])
        XCTAssertEqual(mgr.items[0].useCount, 1)
        mgr.copyToClipboard(mgr.items[0])
        XCTAssertEqual(mgr.items[0].useCount, 2)
    }

    // MARK: - Persistence

    func testSaveCalledOnAdd() {
        let mgr = makeManager()
        let initialCount = historyStore.saveCallCount
        mgr.addTextItem(content: "test")
        // Give debounce time to fire
        let expectation = expectation(description: "persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertGreaterThan(historyStore.saveCallCount, initialCount)
    }


    // MARK: - Hot Window

    func testHotWindowLimitsMemoryItems() {
        prefsStore.hotWindowCount = 500
        let seeded = (0..<1_200).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: Date().addingTimeInterval(TimeInterval(-i)))
        }
        historyStore.seed(seeded)
        let mgr = makeManager()
        XCTAssertEqual(mgr.hotWindowCount, 500)
        XCTAssertLessThanOrEqual(mgr.items.count, 500)
        XCTAssertEqual(mgr.totalStoredCount, 1_200)
    }

    func testHotWindowExpandLoadsMoreFromStore() {
        prefsStore.hotWindowCount = 500
        let seeded = (0..<1_200).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: Date().addingTimeInterval(TimeInterval(-i)))
        }
        historyStore.seed(seeded)
        let mgr = makeManager()
        XCTAssertEqual(mgr.items.count, 500)
        mgr.hotWindowCount = 1_000
        XCTAssertEqual(mgr.items.count, 1_000)
        XCTAssertEqual(mgr.totalStoredCount, 1_200)
    }

    func testHotWindowShrinkDropsColdMemoryOnly() {
        prefsStore.hotWindowCount = 1_000
        let seeded = (0..<1_200).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: Date().addingTimeInterval(TimeInterval(-i)))
        }
        historyStore.seed(seeded)
        let mgr = makeManager()
        XCTAssertEqual(mgr.items.count, 1_000)
        mgr.hotWindowCount = 500
        XCTAssertEqual(mgr.items.count, 500)
        XCTAssertEqual(try historyStore.itemCount(), 1_200)
    }

    func testHotWindowKeepsPinnedWhenShrinking() {
        prefsStore.hotWindowCount = 1_000
        let pinned = ClipboardItem(content: "keep-pin", type: .text, timestamp: Date().addingTimeInterval(-10_000), isPinned: true)
        let seeded = [pinned] + (0..<800).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: Date().addingTimeInterval(TimeInterval(-i)))
        }
        historyStore.seed(seeded)
        let mgr = makeManager()
        mgr.hotWindowCount = 500
        XCTAssertTrue(mgr.items.contains(where: { $0.content == "keep-pin" && $0.isPinned }))
        XCTAssertLessThanOrEqual(mgr.items.count, 500)
    }

    func testCleanupExpiredColdItems() {
        prefsStore.hotWindowCount = 500
        let now = Date()
        let hot = ClipboardItem(content: "hot", type: .text, timestamp: now)
        let coldExpired = ClipboardItem(
            content: "cold-expired",
            type: .text,
            timestamp: now.addingTimeInterval(-100_000),
            expiresAt: now.addingTimeInterval(-1)
        )
        let seeded = [hot] + (0..<600).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: now.addingTimeInterval(TimeInterval(-i - 1)))
        } + [coldExpired]
        historyStore.seed(seeded)
        let mgr = makeManager()
        XCTAssertFalse(mgr.items.contains(where: { $0.content == "cold-expired" }))
        XCTAssertNil(try historyStore.loadItem(id: coldExpired.id))
        XCTAssertEqual(try historyStore.itemCount(), seeded.count - 1)
        XCTAssertEqual(mgr.totalStoredCount, seeded.count - 1)
    }

    func testCleanupAutoDeletesColdOlderThanInterval() {
        prefsStore.hotWindowCount = 500
        prefsStore.autoCleanupInterval = 7
        let now = Date()
        let hot = ClipboardItem(content: "hot", type: .text, timestamp: now)
        let coldOld = ClipboardItem(
            content: "cold-old",
            type: .text,
            timestamp: now.addingTimeInterval(-30 * 86400)
        )
        let seeded = [hot] + (0..<600).map { i in
            ClipboardItem(content: "seed \(i)", type: .text, timestamp: now.addingTimeInterval(TimeInterval(-i - 1)))
        } + [coldOld]
        historyStore.seed(seeded)
        let mgr = makeManager()
        XCTAssertEqual(mgr.autoCleanupInterval, 7)
        XCTAssertNil(try historyStore.loadItem(id: coldOld.id))
        XCTAssertEqual(try historyStore.itemCount(), seeded.count - 1)
        XCTAssertEqual(mgr.totalStoredCount, seeded.count - 1)
    }

    func testTrimToLimitRemovesOldestUnpinned() {
        let mgr = makeManager()
        mgr.maxHistoryCount = 3
        mgr.addTextItem(content: "1")
        mgr.addTextItem(content: "2")
        mgr.addTextItem(content: "3")
        mgr.addTextItem(content: "4")
        XCTAssertEqual(mgr.items.count, 3)
        XCTAssertEqual(mgr.items.map(\.content), ["4", "3", "2"])
        XCTAssertEqual(try historyStore.itemCount(), 3)
    }

    func testTrimToLimitKeepsPinnedBeyondUnpinnedBudget() {
        let mgr = makeManager()
        mgr.maxHistoryCount = 2
        mgr.addTextItem(content: "keep", autoPin: true)
        mgr.addTextItem(content: "a")
        mgr.addTextItem(content: "b")
        XCTAssertTrue(mgr.items.contains(where: { $0.content == "keep" && $0.isPinned }))
        XCTAssertEqual(mgr.items.filter { !$0.isPinned }.count, 1)
        XCTAssertLessThanOrEqual(mgr.items.count, 2)
    }
}
