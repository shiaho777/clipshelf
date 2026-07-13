import XCTest
@testable import ClipboardManager

final class SQLiteHistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: SQLiteHistoryStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SQLiteHistoryStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Basic CRUD

    func testEmptyLoad() throws {
        let items = try store.loadItems()
        XCTAssertTrue(items.isEmpty)
    }

    func testSaveAndLoad() throws {
        let item = ClipboardItem(content: "hello", type: .text)
        try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, "hello")
        XCTAssertEqual(loaded[0].id, item.id)
    }

    func testSaveMultipleItems() throws {
        let items = (1...5).map { ClipboardItem(content: "item \($0)", type: .text) }
        try store.saveItems(items)
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 5)
    }

    func testSavePreservesAllFields() throws {
        let item = ClipboardItem(
            content: "test", rtfData: "rtf".data(using: .utf8), type: .richText,
            isPinned: true, useCount: 3, imageHash: "abc",
            imageFileName: "img.png", ocrText: "ocr",
            sourceBundleID: "com.test", sourceAppName: "Test",
            isSensitive: true, expiresAt: Date(timeIntervalSince1970: 1700000000)
        )
        try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        let l = loaded[0]
        XCTAssertEqual(l.content, "test")
        XCTAssertEqual(l.rtfData, "rtf".data(using: .utf8))
        XCTAssertEqual(l.type, .richText)
        XCTAssertTrue(l.isPinned)
        XCTAssertEqual(l.useCount, 3)
        XCTAssertEqual(l.imageHash, "abc")
        XCTAssertEqual(l.imageFileName, "img.png")
        XCTAssertEqual(l.ocrText, "ocr")
        XCTAssertEqual(l.sourceBundleID, "com.test")
        XCTAssertEqual(l.sourceAppName, "Test")
        XCTAssertTrue(l.isSensitive)
        XCTAssertNotNil(l.expiresAt)
    }

    // MARK: - Diff-based save

    func testNoChangeReturnsFalse() throws {
        let items = [ClipboardItem(content: "hello", type: .text)]
        try store.saveItems(items)
        _ = try store.loadItems()  // snapshot
        let changed = try store.saveItems(items)
        XCTAssertFalse(changed, "No-op save should return false")
    }

    func testDiffInsert() throws {
        let item1 = ClipboardItem(content: "a", type: .text)
        try store.saveItems([item1])
        _ = try store.loadItems()
        let item2 = ClipboardItem(content: "b", type: .text)
        try store.saveItems([item1, item2])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 2)
    }

    func testDiffDelete() throws {
        let item1 = ClipboardItem(content: "a", type: .text)
        let item2 = ClipboardItem(content: "b", type: .text)
        try store.saveItems([item1, item2])
        _ = try store.loadItems()
        _ = try store.deleteItems(ids: [item2.id])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item1.id)
    }

    func testSaveItemsDoesNotDeleteColdItems() throws {
        let item1 = ClipboardItem(content: "hot", type: .text)
        let item2 = ClipboardItem(content: "cold", type: .text)
        try store.saveItems([item1, item2])
        _ = try store.loadItems()
        try store.saveItems([item1])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 2)
    }

    func testLoadItemsLimitKeepsPinned() throws {
        var pinned = ClipboardItem(content: "pin", type: .text)
        pinned.isPinned = true
        let a = ClipboardItem(content: "a", type: .text)
        let b = ClipboardItem(content: "b", type: .text)
        try store.saveItems([pinned, a, b])
        let loaded = try store.loadItems(limit: 2)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains(where: { $0.id == pinned.id }))
    }

    func testTrimUnpinned() throws {
        let items = (0..<5).map { ClipboardItem(content: "i\($0)", type: .text) }
        try store.saveItems(items)
        let removed = try store.trimUnpinned(to: 2)
        XCTAssertEqual(removed.count, 3)
        XCTAssertEqual(try store.itemCount(), 2)
    }

    func testDiffUpdate() throws {
        var item = ClipboardItem(content: "original", type: .text)
        try store.saveItems([item])
        _ = try store.loadItems()
        item.content = "updated"
        try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, "updated")
    }

    func testBatchDiffSaveHandlesLargeMixedChanges() throws {
        let original = (0..<1_000).map { ClipboardItem(content: "item-\($0)", type: .text) }
        try store.saveItems(original)
        _ = try store.loadItems()

        let removedIDs = Set(original.prefix(100).map(\.id))
        _ = try store.deleteItems(ids: removedIDs)

        var updated = Array(original.dropFirst(100))
        for index in 0..<500 {
            updated[index].content = "updated-\(index)"
            updated[index].useCount = index
        }
        updated.append(contentsOf: (0..<100).map { ClipboardItem(content: "new-\($0)", type: .text) })

        let changed = try store.saveItems(updated)
        let loaded = try store.loadItems()
        let loadedByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })

        XCTAssertTrue(changed)
        XCTAssertEqual(loaded.count, 1_000)
        XCTAssertNil(loadedByID[original[0].id])
        XCTAssertEqual(loadedByID[updated[0].id]?.content, "updated-0")
        XCTAssertEqual(loadedByID[updated[499].id]?.useCount, 499)
        XCTAssertTrue(loaded.contains { $0.content == "new-99" })
    }

    func testBatchUpdateUseCounts() throws {
        let item1 = ClipboardItem(content: "a", type: .text)
        let item2 = ClipboardItem(content: "b", type: .text)
        try store.saveItems([item1, item2])
        _ = try store.loadItems()

        let changed = try store.updateUseCounts([item1.id: 3, item2.id: 7])
        let loaded = try store.loadItems()
        let counts = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.useCount) })

        XCTAssertTrue(changed)
        XCTAssertEqual(counts[item1.id], 3)
        XCTAssertEqual(counts[item2.id], 7)
    }

    // MARK: - Migration

    func testMigrateFromJSON() throws {
        let jsonURL = tempDir.appendingPathComponent("history.json")
        let items = [ClipboardItem(content: "migrated", type: .text)]
        let data = try JSONEncoder().encode(items)
        try data.write(to: jsonURL)

        let newStore = SQLiteHistoryStore(storageDirectory: tempDir)
        let migrated = newStore.migrateFromJSON(storageDirectory: tempDir)
        XCTAssertTrue(migrated)

        let loaded = try newStore.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, "migrated")

        // Original file should be renamed
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.appendingPathExtension("migrated").path))
    }

    func testMigrateNoJSONFile() {
        let result = store.migrateFromJSON(storageDirectory: tempDir)
        XCTAssertFalse(result)
    }

    // MARK: - Ordering

    func testPinnedItemsFirst() throws {
        let pinned = ClipboardItem(content: "pinned", type: .text, timestamp: Date().addingTimeInterval(-100), isPinned: true)
        let recent = ClipboardItem(content: "recent", type: .text, timestamp: Date())
        try store.saveItems([recent, pinned])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded[0].content, "pinned", "Pinned items should come first")
    }

    func testFTSSearchFindsContent() throws {
        try store.saveItems([
            ClipboardItem(content: "alpha uniquekeyword zeta", type: .text),
            ClipboardItem(content: "unrelated note", type: .text)
        ])
        _ = try store.loadItems()
        let ids = store.searchFTS("uniquekeyword", limit: 10)
        XCTAssertEqual(ids.count, 1)
    }

    func testLoadItemsLimitPrefersPinned() throws {
        var pinnedOld = ClipboardItem(content: "old pin", type: .text, timestamp: Date().addingTimeInterval(-1000))
        pinnedOld.isPinned = true
        var pinnedNew = ClipboardItem(content: "new pin", type: .text, timestamp: Date())
        pinnedNew.isPinned = true
        let unpinned = (0..<5).map { i in
            ClipboardItem(content: "u\(i)", type: .text, timestamp: Date().addingTimeInterval(TimeInterval(-i)))
        }
        try store.saveItems([pinnedOld, pinnedNew] + unpinned)
        let loaded = try store.loadItems(limit: 3)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.filter(\.isPinned).count, 2)
        XCTAssertTrue(loaded.contains(where: { $0.content == "u0" }))
    }

    // MARK: - Cold cleanup

    func testDeleteExpiredRemovesOnlyExpiredRows() throws {
        let now = Date()
        let active = ClipboardItem(content: "active", type: .text, expiresAt: now.addingTimeInterval(3600))
        let expired = ClipboardItem(content: "expired", type: .text, expiresAt: now.addingTimeInterval(-10))
        let plain = ClipboardItem(content: "plain", type: .text)
        try store.saveItems([active, expired, plain])
        let deleted = try store.deleteExpired(before: now)
        XCTAssertEqual(deleted, [expired.id])
        let loaded = try store.loadItems()
        XCTAssertEqual(Set(loaded.map(\.id)), [active.id, plain.id])
    }

    func testDeleteUnpinnedOlderThanKeepsPinnedAndRecent() throws {
        let now = Date()
        let oldUnpinned = ClipboardItem(content: "old", type: .text, timestamp: now.addingTimeInterval(-30 * 86400))
        let recent = ClipboardItem(content: "recent", type: .text, timestamp: now)
        let oldPinned = ClipboardItem(
            content: "pin",
            type: .text,
            timestamp: now.addingTimeInterval(-30 * 86400),
            isPinned: true
        )
        try store.saveItems([oldUnpinned, recent, oldPinned])
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let deleted = try store.deleteUnpinnedOlderThan(cutoff)
        XCTAssertEqual(deleted, [oldUnpinned.id])
        let loaded = try store.loadItems()
        XCTAssertEqual(Set(loaded.map(\.id)), [recent.id, oldPinned.id])
    }

    func testDeleteExpiredIsIdempotent() throws {
        let now = Date()
        let expired = ClipboardItem(content: "expired", type: .text, expiresAt: now.addingTimeInterval(-1))
        try store.saveItems([expired])
        XCTAssertEqual(try store.deleteExpired(before: now), [expired.id])
        XCTAssertTrue(try store.deleteExpired(before: now).isEmpty)
        XCTAssertTrue(try store.loadItems().isEmpty)
    }
}
