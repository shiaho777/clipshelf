import XCTest
@testable import ClipboardManager

final class TextTransformAdvancedTests: XCTestCase {

    // MARK: - Hex encode / decode

    func testHexEncode() {
        let result = TextTransform.hexEncode.apply("Hello")
        XCTAssertEqual(result, "48656c6c6f")
    }

    func testHexDecode() {
        let result = TextTransform.hexDecode.apply("48656c6c6f")
        XCTAssertEqual(result, "Hello")
    }

    func testHexRoundtrip() {
        let original = "Swift 🚀 UTF-8"
        let encoded = TextTransform.hexEncode.apply(original)!
        let decoded = TextTransform.hexDecode.apply(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testHexDecodeOddLengthReturnsNil() {
        XCTAssertNil(TextTransform.hexDecode.apply("abc"))
    }

    func testHexDecodeInvalidCharsReturnsNil() {
        XCTAssertNil(TextTransform.hexDecode.apply("0g"))
    }

    // MARK: - SHA-256

    func testSha256KnownVector() {
        // SHA-256("hello") is a well-known test vector
        let result = TextTransform.sha256Hash.apply("hello")
        XCTAssertEqual(result, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testSha256EmptyString() {
        let result = TextTransform.sha256Hash.apply("")
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        XCTAssertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSha256Length() {
        let result = TextTransform.sha256Hash.apply("any input")!
        XCTAssertEqual(result.count, 64) // 32 bytes → 64 hex chars
    }

    // MARK: - JSON escape

    func testJsonEscapeQuotes() {
        let result = TextTransform.jsonEscape.apply(#"say "hello""#)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(#"\""#))
    }

    func testJsonEscapeNewline() {
        let result = TextTransform.jsonEscape.apply("line1\nline2")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(#"\n"#))
    }

    func testJsonEscapeRoundtrip() throws {
        let original = #"hello "world"\nnewline"#
        let escaped = try XCTUnwrap(TextTransform.jsonEscape.apply(original))
        // Wrap in JSON object and parse back to verify validity
        guard let data = "{\"\": \"\(escaped)\"}".data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            XCTFail("JSON produced by jsonEscape is not parseable")
            return
        }
        XCTAssertEqual(obj[""], original)
    }

    // MARK: - Swift string literal

    func testSwiftStringLiteralNewline() {
        let result = TextTransform.swiftStringLiteral.apply("Hello\nWorld")
        XCTAssertEqual(result, "\"Hello\\nWorld\"")
    }

    func testSwiftStringLiteralTab() {
        let result = TextTransform.swiftStringLiteral.apply("a\tb")
        XCTAssertEqual(result, "\"a\\tb\"")
    }

    func testSwiftStringLiteralBackslash() {
        let result = TextTransform.swiftStringLiteral.apply("C:\\Users\\test")
        XCTAssertEqual(result, "\"C:\\\\Users\\\\test\"")
    }

    // MARK: - JavaScript string literal

    func testJsStringLiteralQuotes() {
        let result = TextTransform.jsStringLiteral.apply(#"say "hi""#)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(#"\""#))
    }

    func testJsStringLiteralTab() {
        let result = TextTransform.jsStringLiteral.apply("col1\tcol2")
        XCTAssertEqual(result, "\"col1\\tcol2\"")
    }

    // MARK: - HTML entities encode / decode

    func testHtmlEntitiesEncode() {
        let result = TextTransform.htmlEntitiesEncode.apply("<b>bold & safe</b>")
        XCTAssertEqual(result, "&lt;b&gt;bold &amp; safe&lt;/b&gt;")
    }

    func testHtmlEntitiesDecodeBasic() {
        let result = TextTransform.htmlEntitiesDecode.apply("&lt;b&gt;bold&lt;/b&gt;")
        XCTAssertEqual(result, "<b>bold</b>")
    }

    func testHtmlEntitiesRoundtrip() {
        let original = "<script>alert('xss')</script>"
        let encoded = TextTransform.htmlEntitiesEncode.apply(original)!
        let decoded = TextTransform.htmlEntitiesDecode.apply(encoded)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - XML format

    func testXmlFormatValidInput() {
        let input = "<root><child>text</child></root>"
        let result = TextTransform.xmlFormat.apply(input)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("<child>"))
    }

    func testXmlFormatInvalidInputReturnsNil() {
        let input = "<unclosed"
        let result = TextTransform.xmlFormat.apply(input)
        XCTAssertNil(result)
    }
}
