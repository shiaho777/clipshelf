import XCTest
@testable import ClipShelf

final class SQLiteMigrationV3Tests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteV3Test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Schema version

    func testCurrentSchemaVersion() {
        XCTAssertEqual(SQLiteHistoryStore.currentSchemaVersion, 5)
    }

    func testMigrationsCount() {
        XCTAssertEqual(SQLiteHistoryStore.migrations.count, 5)
    }

    // MARK: - Fresh database

    func testFreshDatabaseLoadsWithoutError() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        XCTAssertNoThrow(try store.loadItems())
    }

    func testFreshDatabaseIsEmpty() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        let items = try store.loadItems()
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Basic roundtrip

    func testBasicItemRoundtrip() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        let item = ClipboardItem(content: "hello sqlite", type: .text)
        _ = try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "hello sqlite")
    }

    // MARK: - v3 columns

    func testSensitiveItemRoundtrip() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        let item = ClipboardItem(content: "super-secret", type: .text, isSensitive: true)
        _ = try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.isSensitive, true)
        XCTAssertEqual(loaded.first?.content, "super-secret")
    }

    func testMultipleItemsWithMixedSensitivity() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        let normal = ClipboardItem(content: "public", type: .text, isSensitive: false)
        let secret = ClipboardItem(content: "private", type: .text, isSensitive: true)
        _ = try store.saveItems([normal, secret])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 2)
        let sensitiveCount = loaded.filter { $0.isSensitive }.count
        XCTAssertEqual(sensitiveCount, 1)
    }

    // MARK: - Idempotency

    func testMigrationsAreIdempotent() throws {
        // Opening two stores against the same DB file must not corrupt it
        let store1 = SQLiteHistoryStore(storageDirectory: tmpDir)
        let item = ClipboardItem(content: "idempotent", type: .text)
        _ = try store1.saveItems([item])

        let store2 = SQLiteHistoryStore(storageDirectory: tmpDir)
        let loaded = try store2.loadItems()
        XCTAssertEqual(loaded.first?.content, "idempotent")
    }

    // MARK: - FTS search (v2 column)

    func testFTSSearchReturnsMatchingID() throws {
        let store = SQLiteHistoryStore(storageDirectory: tmpDir)
        let item = ClipboardItem(content: "uniqueword_xyz", type: .text)
        _ = try store.saveItems([item])
        let ids = store.searchFTS("uniqueword")
        XCTAssertTrue(ids.contains(item.id))
    }
}
