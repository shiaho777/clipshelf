import XCTest
@testable import ClipShelf

final class FuzzySearchTests: XCTestCase {

    private func makeItems(_ contents: [String]) -> [ClipboardItem] {
        contents.map { ClipboardItem(content: $0, type: .text) }
    }

    // MARK: - Basic

    func testEmptyQueryReturnsAll() {
        let items = makeItems(["a", "b", "c"])
        let results = FuzzySearch.search("", in: items)
        XCTAssertEqual(results.count, 3)
    }

    func testWhitespaceOnlyQueryReturnsAll() {
        let items = makeItems(["a"])
        XCTAssertEqual(FuzzySearch.search("   ", in: items).count, 1)
    }

    func testExactMatch() {
        let items = makeItems(["Hello World", "Goodbye World"])
        let results = FuzzySearch.search("Hello", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "Hello World")
    }

    func testCaseInsensitive() {
        let items = makeItems(["HELLO world"])
        let results = FuzzySearch.search("hello", in: items)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Subsequence Matching

    func testSubsequenceMatch() {
        let items = makeItems(["backgroundColor", "background", "color"])
        let results = FuzzySearch.search("bgc", in: items)
        // "backgroundColor" should match bgc as subsequence (b-g-c-olor)
        XCTAssertTrue(results.contains(where: { $0.content == "backgroundColor" }))
    }

    func testSubsequenceNoMatch() {
        let items = makeItems(["abc"])
        let results = FuzzySearch.search("xyz", in: items)
        XCTAssertTrue(results.isEmpty)
    }

    func testTypoPartialMatch() {
        // "colr" should fuzzy-match "color" as subsequence c-o-l-r
        let items = makeItems(["color", "something else"])
        let results = FuzzySearch.search("colr", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "color")
    }

    // MARK: - Scoring

    func testExactMatchScoresHigherThanFuzzy() {
        let items = makeItems(["color", "controller"])
        let results = FuzzySearch.search("color", in: items)
        // "color" is exact match, should come first
        XCTAssertEqual(results.first?.content, "color")
    }

    func testPrefixMatchScoresHigher() {
        let items = makeItems(["prefix_match", "no_prefix"])
        let results = FuzzySearch.search("prefix", in: items)
        XCTAssertEqual(results.first?.content, "prefix_match")
    }

    // MARK: - Multi-token

    func testMultiTokenSearch() {
        let items = makeItems(["Swift programming language", "Swift bird", "programming tutorial"])
        let results = FuzzySearch.search("swift programming", in: items)
        XCTAssertEqual(results.first?.content, "Swift programming language")
    }

    // MARK: - Chinese

    func testChineseSearch() {
        let items = makeItems(["剪贴板管理器", "文本编辑器"])
        let results = FuzzySearch.search("剪贴板", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "剪贴板管理器")
    }

    // MARK: - OCR Text

    func testImageOCRTextSearch() {
        let item = ClipboardItem(type: .image, imageHash: "abc", imageFileName: "test.png", ocrText: "Invoice #12345")
        let results = FuzzySearch.search("invoice", in: [item])
        XCTAssertEqual(results.count, 1)
    }

    func testImageWithoutOCRTextNotMatched() {
        let item = ClipboardItem(type: .image, imageHash: "abc", imageFileName: "test.png")
        let results = FuzzySearch.search("anything", in: [item])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Subsequence Score Function

    func testSubsequenceScoreReturnsNilOnNoMatch() {
        XCTAssertNil(FuzzySearch.subsequenceScore(query: "xyz", in: "abc", original: "abc"))
    }

    func testSubsequenceScoreEmptyQuery() {
        XCTAssertEqual(FuzzySearch.subsequenceScore(query: "", in: "abc", original: "abc"), 0)
    }

    func testSubsequenceScoreConsecutiveBonus() {
        let consecutive = FuzzySearch.subsequenceScore(query: "ab", in: "abc", original: "abc")!
        let scattered = FuzzySearch.subsequenceScore(query: "ac", in: "abc", original: "abc")!
        XCTAssertGreaterThan(consecutive, scattered)
    }

    // MARK: - ParsedQuery / Advanced Syntax

    func testParseQueryExtractsAppFilter() {
        let parsed = FuzzySearch.parseQuery("app:com.apple.Safari hello")
        XCTAssertEqual(parsed.appFilter, "com.apple.safari")
        XCTAssertEqual(parsed.textTokens, ["hello"])
    }

    func testParseQueryExtractsTypeFilter() {
        let parsed = FuzzySearch.parseQuery("type:image")
        XCTAssertEqual(parsed.typeFilter, .image)
        XCTAssertTrue(parsed.textTokens.isEmpty)
    }

    func testParseQueryExtractsTypeText() {
        let parsed = FuzzySearch.parseQuery("type:text hello world")
        XCTAssertEqual(parsed.typeFilter, .text)
        XCTAssertEqual(parsed.textTokens, ["hello", "world"])
    }

    func testParseQueryExtractsTypeRichText() {
        let parsed = FuzzySearch.parseQuery("type:rich")
        XCTAssertEqual(parsed.typeFilter, .richText)
    }

    func testParseQueryUnknownTypeBecomesTextToken() {
        let parsed = FuzzySearch.parseQuery("type:unknown")
        XCTAssertNil(parsed.typeFilter)
        XCTAssertEqual(parsed.textTokens, ["type:unknown"])
    }

    func testParseQueryNoFilters() {
        let parsed = FuzzySearch.parseQuery("hello world")
        XCTAssertNil(parsed.appFilter)
        XCTAssertNil(parsed.typeFilter)
        XCTAssertEqual(parsed.textTokens, ["hello", "world"])
    }

    func testSearchWithAppFilterFiltersItems() {
        var item1 = ClipboardItem(content: "safari content", type: .text)
        item1.sourceBundleID = "com.apple.Safari"
        var item2 = ClipboardItem(content: "chrome content", type: .text)
        item2.sourceBundleID = "com.google.Chrome"
        let results = FuzzySearch.search("app:safari", in: [item1, item2])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sourceBundleID, "com.apple.Safari")
    }

    func testSearchWithTypeFilterFiltersItems() {
        let textItem = ClipboardItem(content: "hello", type: .text)
        let imageItem = ClipboardItem(type: .image, imageHash: "abc", imageFileName: "test.png")
        let results = FuzzySearch.search("type:text", in: [textItem, imageItem])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, .text)
    }
}
