import XCTest
@testable import ClipShelf

final class ShortQueryFTSTests: XCTestCase {
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

    func testTwoCharacterChineseQueryMatchesViaFTS() throws {
        let target = ClipboardItem(content: "上周的发票已经报销", type: .text)
        let other = ClipboardItem(content: "完全无关的内容", type: .text)
        try store.saveItems([target, other])
        let ids = store.searchFTS("发票")
        XCTAssertEqual(ids, [target.id])
    }

    func testTwoCharacterChineseQuerySanitizedToPhrase() {
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("发票"), "\"发票\"")
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("密码 找回"), "\"密码\" \"找回\"")
    }

    func testShortAsciiTokensStillDropped() {
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("ab"), "")
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("abc"), "abc")
    }

    func testReservedWordsStillFiltered() {
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("AND OR NOT"), "")
        XCTAssertEqual(SQLiteHistoryStore.sanitizeFTSQuery("发票 AND"), "\"发票\"")
    }

    func testBatchLoadReturnsRequestedItems() throws {
        let items = (0..<5).map { ClipboardItem(content: "batch \($0)", type: .text) }
        try store.saveItems(items)
        let requested = [items[0].id, items[2].id, items[4].id]
        let loaded = try store.loadItems(ids: requested)
        XCTAssertEqual(loaded.count, 3)
        for id in requested {
            XCTAssertEqual(loaded[id]?.id, id)
        }
    }

    func testBatchLoadWithUnknownIDsSkipsThem() throws {
        let item = ClipboardItem(content: "known", type: .text)
        try store.saveItems([item])
        let loaded = try store.loadItems(ids: [item.id, UUID()])
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[item.id]?.content, "known")
    }

    func testBatchLoadEmptyReturnsEmpty() throws {
        XCTAssertTrue(try store.loadItems(ids: []).isEmpty)
    }
}

final class SemanticQueryLanguageTests: XCTestCase {
    func testChineseQueryIsNotEnglish() {
        XCTAssertFalse(SemanticSearchService.isLikelyEnglishQuery("发票"))
        XCTAssertFalse(SemanticSearchService.isLikelyEnglishQuery("找回密码"))
    }

    func testEnglishQueryIsEnglish() {
        XCTAssertTrue(SemanticSearchService.isLikelyEnglishQuery("invoice"))
        XCTAssertTrue(SemanticSearchService.isLikelyEnglishQuery("reset my password"))
    }

    func testMixedQueryBelowThresholdIsNotEnglish() {
        XCTAssertFalse(SemanticSearchService.isLikelyEnglishQuery("发票invoice发票发票"))
    }

    func testSymbolOnlyQueryIsNotEnglish() {
        XCTAssertFalse(SemanticSearchService.isLikelyEnglishQuery("12345"))
        XCTAssertFalse(SemanticSearchService.isLikelyEnglishQuery(""))
    }
}

final class MonitorCadenceTests: XCTestCase {
    func testDeepIdleCapKeepsCaptureLatencyBounded() {
        XCTAssertLessThanOrEqual(ClipboardMonitor.Cadence.deepIdle, 3.0)
        XCTAssertLessThanOrEqual(ClipboardMonitor.Cadence.idle, 2.0)
        XCTAssertGreaterThan(ClipboardMonitor.Cadence.deepIdle, ClipboardMonitor.Cadence.idle)
    }
}

@MainActor
final class IngestPipelineDrainTests: XCTestCase {
    func testDrainWaitsForPendingProcessing() async {
        let engine = ClipboardRuleEngine()
        var stored: [String] = []
        let pipeline = ClipboardIngestPipeline(ruleEngine: engine) { content, _, _, _ in
            if case .text(let text) = content.kind { stored.append(text) }
        }
        pipeline.handle(CapturedContent(kind: .text(content: "first"), sourceBundleID: nil, sourceAppName: nil))
        pipeline.handle(CapturedContent(kind: .text(content: "second"), sourceBundleID: nil, sourceAppName: nil))
        await pipeline.drain(timeout: 5.0)
        XCTAssertEqual(stored, ["first", "second"])
    }

    func testDrainWithoutPendingReturnsImmediately() async {
        let engine = ClipboardRuleEngine()
        let pipeline = ClipboardIngestPipeline(ruleEngine: engine) { _, _, _, _ in }
        await pipeline.drain(timeout: 0.1)
    }
}