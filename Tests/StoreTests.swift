import XCTest
@testable import ClipShelf

final class JSONClipboardHistoryStoreTests: XCTestCase {

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

    // MARK: - Roundtrip

    func testSaveAndLoadRoundtrip() throws {
        let store = JSONClipboardHistoryStore(storageDirectory: tempDir)
        let items = [
            ClipboardItem(content: "text item", type: .text),
            ClipboardItem(content: "rich", rtfData: "rtf".data(using: .utf8), type: .richText),
            ClipboardItem(content: "", type: .image, imageHash: "abc123", imageFileName: "img.png")
        ]
        try store.saveItems(items)
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].content, "text item")
        XCTAssertEqual(loaded[1].type, .richText)
        XCTAssertEqual(loaded[2].imageHash, "abc123")
        XCTAssertEqual(loaded[2].imageFileName, "img.png")
    }

    func testSavePreservesAllFields() throws {
        let store = JSONClipboardHistoryStore(storageDirectory: tempDir)
        let item = ClipboardItem(content: "test", type: .text, isPinned: true, useCount: 5)
        try store.saveItems([item])
        let loaded = try store.loadItems()
        XCTAssertEqual(loaded[0].isPinned, true)
        XCTAssertEqual(loaded[0].useCount, 5)
        XCTAssertEqual(loaded[0].id, item.id)
    }

    // MARK: - Skip Unchanged

    func testSkipUnchangedWrite() throws {
        let store = JSONClipboardHistoryStore(storageDirectory: tempDir)
        let items = [ClipboardItem(content: "stable", type: .text)]
        let wrote1 = try store.saveItems(items)
        XCTAssertTrue(wrote1)
        let wrote2 = try store.saveItems(items)
        XCTAssertFalse(wrote2, "Should skip writing identical content")
    }

    // MARK: - Empty State

    func testLoadFromEmptyDirectory() throws {
        let store = JSONClipboardHistoryStore(storageDirectory: tempDir)
        let items = try store.loadItems()
        XCTAssertTrue(items.isEmpty)
    }
}

// MARK: - JSONAppPreferencesStoreTests

final class JSONAppPreferencesStoreTests: XCTestCase {

    private var tempDir: URL!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        userDefaults = UserDefaults(suiteName: UUID().uuidString)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        userDefaults.removePersistentDomain(forName: userDefaults.volatileDomainNames.first ?? "")
        super.tearDown()
    }

    private func makeStore() -> JSONAppPreferencesStore {
        JSONAppPreferencesStore(storageDirectory: tempDir, userDefaults: userDefaults)
    }

    // MARK: - Language

    func testLanguageSaveAndLoad() throws {
        let store = makeStore()
        try store.saveLanguage("zh")
        XCTAssertEqual(try store.loadLanguage(), "zh")
    }

    func testLanguageFallbackToUserDefaults() throws {
        userDefaults.set("en", forKey: "appLanguage")
        let store = makeStore()
        XCTAssertEqual(try store.loadLanguage(), "en")
    }

    func testLanguageNilWhenNoData() throws {
        let store = makeStore()
        XCTAssertNil(try store.loadLanguage())
    }

    // MARK: - Launch at Login

    func testLaunchAtLoginSaveAndLoad() throws {
        let store = makeStore()
        try store.saveLaunchAtLogin(true)
        XCTAssertEqual(try store.loadLaunchAtLogin(), true)
    }

    // MARK: - Max History Count

    func testMaxHistoryCountSaveAndLoad() throws {
        let store = makeStore()
        try store.saveMaxHistoryCount(200)
        XCTAssertEqual(try store.loadMaxHistoryCount(), 200)
    }

    func testMaxHistoryCountFallbackToUserDefaults() throws {
        userDefaults.set(500, forKey: "maxHistoryCount")
        let store = makeStore()
        XCTAssertEqual(try store.loadMaxHistoryCount(), 500)
    }

    // MARK: - Auto Cleanup Interval

    func testAutoCleanupIntervalSaveAndLoad() throws {
        let store = makeStore()
        try store.saveAutoCleanupInterval(7)
        XCTAssertEqual(try store.loadAutoCleanupInterval(), 7)
    }

    // MARK: - Excluded Bundle IDs

    func testExcludedBundleIDsSaveAndLoad() throws {
        let store = makeStore()
        let ids: Set<String> = ["com.example.app1", "com.example.app2"]
        try store.saveExcludedBundleIDs(ids)
        XCTAssertEqual(try store.loadExcludedBundleIDs(), ids)
    }

    func testExcludedBundleIDsLegacyFallback() throws {
        let legacy: Set<String> = ["com.legacy.app"]
        let legacyData = try JSONEncoder().encode(legacy)
        userDefaults.set(legacyData, forKey: "excludedApps")
        let store = makeStore()
        XCTAssertEqual(try store.loadExcludedBundleIDs(), legacy)
    }
}
