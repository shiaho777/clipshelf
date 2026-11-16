import XCTest
@testable import ClipShelf

final class StorePerformanceRegressionTests: XCTestCase {
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

    private func makeItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { i in
            ClipboardItem(
                content: "item \(i) keyword benchmark text variant \(i % 100)",
                type: .text,
                sourceAppName: i.isMultiple(of: 2) ? "Safari" : "Notes"
            )
        }
    }

    func testUseCountUpdateKeepsFTSIndexIntact() throws {
        let items = makeItems(count: 20)
        try store.saveItems(items)
        let target = items[3]
        try store.updateUseCount(id: target.id, useCount: 9)
        let hits = store.searchFTS("keyword")
        XCTAssertTrue(hits.contains(target.id))
        XCTAssertEqual(hits.count, 20)
    }

    func testEmbeddingUpdateKeepsFTSIndexIntact() throws {
        let items = makeItems(count: 10)
        try store.saveItems(items)
        let target = items[1]
        store.saveEmbedding([Float32](repeating: 0.1, count: 8), for: target.id)
        XCTAssertTrue(store.searchFTS("keyword").contains(target.id))
    }

    func testContentUpdateStillReindexesFTS() throws {
        let items = makeItems(count: 5)
        try store.saveItems(items)
        var edited = items[0]
        edited.content = "zebra unique token"
        try store.upsertItem(edited)
        XCTAssertTrue(store.searchFTS("zebra").contains(edited.id))
        XCTAssertFalse(store.searchFTS("variant 0").contains(edited.id))
    }

    func testOCRBackfillBecomesSearchable() throws {
        let item = ClipboardItem(content: "", type: .image, imageFileName: "x.png")
        try store.saveItems([item])
        var recognized = item
        recognized.ocrText = "发票号码 044172300111"
        try store.upsertItem(recognized)
        XCTAssertTrue(store.searchFTS("发票").contains(item.id))
    }

    func testUnchangedSnapshotSkipsWrite() throws {
        let items = makeItems(count: 50)
        XCTAssertTrue(try store.saveItems(items))
        XCTAssertFalse(try store.saveItems(items))
    }

    func testChangedSnapshotWritesOnlyDiff() throws {
        var items = makeItems(count: 50)
        try store.saveItems(items)
        items[7].useCount = 42
        XCTAssertTrue(try store.saveItems(items))
        let loaded = try store.loadItem(id: items[7].id)
        XCTAssertEqual(loaded?.useCount, 42)
    }

    func testTrimWithinLimitReturnsEmptyWithoutDeleting() throws {
        let items = makeItems(count: 30)
        try store.saveItems(items)
        let removed = try store.trimUnpinned(to: 100)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(try store.itemCount(), 30)
    }

    func testTrimOverLimitRemovesOldest() throws {
        let items = makeItems(count: 30)
        try store.saveItems(items)
        let removed = try store.trimUnpinned(to: 10)
        XCTAssertEqual(removed.count, 20)
        XCTAssertEqual(try store.itemCount(), 10)
    }

    func testSnapshotSavePerformance_2k() throws {
        let items = makeItems(count: 2_000)
        try store.saveItems(items)
        measure {
            _ = try? store.saveItems(items)
        }
    }

    func testUseCountBatchUpdatePerformance_2k() throws {
        let items = makeItems(count: 2_000)
        try store.saveItems(items)
        let updates = Dictionary(uniqueKeysWithValues: items.prefix(200).map { ($0.id, $0.useCount + 1) })
        measure {
            _ = try? store.updateUseCounts(updates)
        }
    }
}