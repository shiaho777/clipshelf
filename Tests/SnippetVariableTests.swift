import XCTest
@testable import ClipShelf

final class SnippetVariableTests: XCTestCase {

    // Fixed reference date: 2024-01-15 10:30:00 UTC
    private let refDate = Date(timeIntervalSince1970: 1_705_314_600)

    // MARK: - {{date:format}}

    func testDateFormatExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "{{date:yyyy-MM-dd}}",
            clipboardText: "",
            now: refDate
        )
        XCTAssertFalse(result.expanded.contains("{{date"))
        XCTAssertTrue(result.expanded.contains("2024"))
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    func testDateNoFormatExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "Today: {{date}}",
            clipboardText: "",
            now: refDate
        )
        XCTAssertFalse(result.expanded.contains("{{date}}"))
        XCTAssertTrue(result.expanded.hasPrefix("Today: "))
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    // MARK: - {{time:format}}

    func testTimeFormatExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "{{time:HH:mm}}",
            clipboardText: "",
            now: refDate
        )
        XCTAssertFalse(result.expanded.contains("{{time"))
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    // MARK: - {{datetime}}

    func testDatetimeExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "{{datetime}}",
            clipboardText: "",
            now: refDate
        )
        XCTAssertFalse(result.expanded.contains("{{datetime}}"))
        // ISO 8601 output always contains the year
        XCTAssertTrue(result.expanded.contains("2024"))
    }

    // MARK: - {{clipboard}}

    func testClipboardExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "Pasted: {{clipboard}}",
            clipboardText: "hello world",
            now: Date()
        )
        XCTAssertEqual(result.expanded, "Pasted: hello world")
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    func testClipboardEmptyExpansion() {
        let result = SnippetVariableEngine.expand(
            template: "{{clipboard}}",
            clipboardText: "",
            now: Date()
        )
        XCTAssertEqual(result.expanded, "")
    }

    // MARK: - {{cursor}}

    func testCursorPlacementMiddle() {
        // "SELECT * FROM {{cursor}} WHERE id = 1;"
        // After cursor:  " WHERE id = 1;" = 14 chars
        let result = SnippetVariableEngine.expand(
            template: "SELECT * FROM {{cursor}} WHERE id = 1;",
            clipboardText: "",
            now: Date()
        )
        XCTAssertEqual(result.expanded, "SELECT * FROM  WHERE id = 1;")
        XCTAssertEqual(result.cursorBackCount, 14)
    }

    func testCursorAtEnd() {
        let result = SnippetVariableEngine.expand(
            template: "prefix {{cursor}}",
            clipboardText: "",
            now: Date()
        )
        XCTAssertEqual(result.expanded, "prefix ")
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    func testNoCursorProducesZeroBackCount() {
        let result = SnippetVariableEngine.expand(
            template: "no cursor here",
            clipboardText: "",
            now: Date()
        )
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    // MARK: - {{random:N}}

    func testRandomLength() {
        let result = SnippetVariableEngine.expand(
            template: "{{random:12}}",
            clipboardText: "",
            now: Date()
        )
        XCTAssertEqual(result.expanded.count, 12)
        XCTAssertFalse(result.expanded.contains("{"))
    }

    func testRandomIsAlphanumeric() {
        let result = SnippetVariableEngine.expand(
            template: "{{random:32}}",
            clipboardText: "",
            now: Date()
        )
        let alphanumeric = CharacterSet.alphanumerics
        XCTAssertTrue(result.expanded.unicodeScalars.allSatisfy { alphanumeric.contains($0) })
    }

    // MARK: - No variables

    func testNoVariablesPassThrough() {
        let result = SnippetVariableEngine.expand(
            template: "plain text snippet",
            clipboardText: "ignored",
            now: Date()
        )
        XCTAssertEqual(result.expanded, "plain text snippet")
        XCTAssertEqual(result.cursorBackCount, 0)
    }

    // MARK: - Combinations

    func testMultipleVariables() {
        let result = SnippetVariableEngine.expand(
            template: "Date: {{date:yyyy}} / Rand: {{random:4}}",
            clipboardText: "",
            now: refDate
        )
        XCTAssertTrue(result.expanded.contains("Date: 2024"))
        XCTAssertFalse(result.expanded.contains("{{"))
        XCTAssertEqual(result.cursorBackCount, 0)
    }
}
