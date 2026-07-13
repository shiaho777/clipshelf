import XCTest
@testable import ClipboardManager

final class HistoryStoreBackupTests: XCTestCase {

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

    private func makeStore() -> JSONClipboardHistoryStore {
        JSONClipboardHistoryStore(storageDirectory: tempDir)
    }

    private func makeItems(_ contents: [String]) -> [ClipboardItem] {
        contents.map { ClipboardItem(content: $0, type: .text) }
    }

    // MARK: - Backup Creation

    func testSaveCreatesBackup() throws {
        let store = makeStore()
        // First save — no backup yet (no prior file to rotate)
        try store.saveItems(makeItems(["v1"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL(1).path),
                        "First save should not create backup (no prior file)")

        // Second save — history.json from v1 becomes .bak.1
        try store.saveItems(makeItems(["v2"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL(1).path),
                       "Second save should create .bak.1")

        // Verify .bak.1 contains v1 data
        let backupData = try Data(contentsOf: store.backupURL(1))
        let backupItems = try JSONDecoder().decode([ClipboardItem].self, from: backupData)
        XCTAssertEqual(backupItems.count, 1)
        XCTAssertEqual(backupItems[0].content, "v1")
    }

    // MARK: - Backup Rotation

    func testBackupRotation() throws {
        let store = makeStore()
        // Save 4 times: v1, v2, v3, v4
        for i in 1...4 {
            try store.saveItems(makeItems(["v\(i)"]))
        }

        // After 4 saves:
        // history.json = v4
        // .bak.1 = v3 (most recent backup)
        // .bak.2 = v2
        // .bak.3 = v1 (oldest backup)

        let decoder = JSONDecoder()
        let bak1 = try decoder.decode([ClipboardItem].self, from: Data(contentsOf: store.backupURL(1)))
        let bak2 = try decoder.decode([ClipboardItem].self, from: Data(contentsOf: store.backupURL(2)))
        let bak3 = try decoder.decode([ClipboardItem].self, from: Data(contentsOf: store.backupURL(3)))

        XCTAssertEqual(bak1[0].content, "v3")
        XCTAssertEqual(bak2[0].content, "v2")
        XCTAssertEqual(bak3[0].content, "v1")
    }

    func testOnlyThreeBackupsKept() throws {
        let store = makeStore()
        for i in 1...6 {
            try store.saveItems(makeItems(["v\(i)"]))
        }
        // .bak.1 = v5, .bak.2 = v4, .bak.3 = v3
        // No .bak.4 should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL(3).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL(4).path))
    }

    // MARK: - Recovery from Corruption

    func testRecoverFromCorruptFile() throws {
        let store = makeStore()
        // Save valid data twice (so .bak.1 exists with v1)
        try store.saveItems(makeItems(["good data"]))
        try store.saveItems(makeItems(["latest"]))

        // Now corrupt history.json
        let historyURL = tempDir.appendingPathComponent("history.json")
        try "NOT VALID JSON{{{".data(using: .utf8)!.write(to: historyURL)

        // Load with a fresh store instance (no cached state)
        let freshStore = makeStore()
        let recovered = try freshStore.loadItems()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].content, "good data",
                        "Should recover from .bak.1 which contains the first save")
    }

    func testRecoverFallsThrough() throws {
        let store = makeStore()
        // Save 3 times to fill all backup slots
        try store.saveItems(makeItems(["oldest"]))
        try store.saveItems(makeItems(["middle"]))
        try store.saveItems(makeItems(["latest"]))

        // Corrupt history.json and .bak.1
        let historyURL = tempDir.appendingPathComponent("history.json")
        try "CORRUPT".data(using: .utf8)!.write(to: historyURL)
        try "CORRUPT".data(using: .utf8)!.write(to: store.backupURL(1))

        let freshStore = makeStore()
        let recovered = try freshStore.loadItems()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].content, "oldest",
                        "Should fall through to .bak.2 when .bak.1 is also corrupt")
    }

    func testAllCorruptThrows() throws {
        let store = makeStore()
        try store.saveItems(makeItems(["data"]))

        // Corrupt everything
        let historyURL = tempDir.appendingPathComponent("history.json")
        try "BAD".data(using: .utf8)!.write(to: historyURL)
        try "BAD".data(using: .utf8)!.write(to: store.backupURL(1))

        let freshStore = makeStore()
        XCTAssertThrowsError(try freshStore.loadItems(),
                             "Should throw when main file and all backups are corrupt")
    }
}
