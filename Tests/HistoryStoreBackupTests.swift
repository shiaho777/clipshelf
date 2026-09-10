import XCTest
@testable import ClipShelf

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

    func testSaveCreatesBackup() throws {
        let store = makeStore()
        try store.saveItems(makeItems(["v1"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL(1).path),
                        "First save should not create backup (no prior file)")

        try store.saveItems(makeItems(["v2"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL(1).path),
                       "Second save should create .bak.1")

        let backupData = try Data(contentsOf: store.backupURL(1))
        let backupItems = try JSONDecoder().decode([ClipboardItem].self, from: backupData)
        XCTAssertEqual(backupItems.count, 1)
        XCTAssertEqual(backupItems[0].content, "v1")
    }

    func testBackupRotation() throws {
        let store = makeStore()
        for i in 1...4 {
            try store.saveItems(makeItems(["v\(i)"]))
        }

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
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL(3).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL(4).path))
    }

    func testRecoverFromCorruptFile() throws {
        let store = makeStore()
        try store.saveItems(makeItems(["good data"]))
        try store.saveItems(makeItems(["latest"]))

        let historyURL = tempDir.appendingPathComponent("history.json")
        try "NOT VALID JSON{{{".data(using: .utf8)!.write(to: historyURL)

        let freshStore = makeStore()
        let recovered = try freshStore.loadItems()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].content, "good data",
                        "Should recover from .bak.1 which contains the first save")
    }

    func testRecoverFallsThrough() throws {
        let store = makeStore()
        try store.saveItems(makeItems(["oldest"]))
        try store.saveItems(makeItems(["middle"]))
        try store.saveItems(makeItems(["latest"]))

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

        let historyURL = tempDir.appendingPathComponent("history.json")
        try "BAD".data(using: .utf8)!.write(to: historyURL)
        try "BAD".data(using: .utf8)!.write(to: store.backupURL(1))

        let freshStore = makeStore()
        XCTAssertThrowsError(try freshStore.loadItems(),
                             "Should throw when main file and all backups are corrupt")
    }
}
