import XCTest
@testable import ClipboardManager

final class TextTransformTests: XCTestCase {

    func testUppercase() {
        XCTAssertEqual(TextTransform.uppercase.apply("hello"), "HELLO")
    }

    func testLowercase() {
        XCTAssertEqual(TextTransform.lowercase.apply("HELLO"), "hello")
    }

    func testCapitalize() {
        XCTAssertEqual(TextTransform.capitalize.apply("hello world"), "Hello World")
    }

    func testTrimWhitespace() {
        XCTAssertEqual(TextTransform.trimWhitespace.apply("  hello  \n  world  "), "hello\nworld")
    }

    func testRemoveBlankLines() {
        XCTAssertEqual(TextTransform.removeBlankLines.apply("a\n\nb\n  \nc"), "a\nb\nc")
    }

    func testUrlEncode() {
        XCTAssertEqual(TextTransform.urlEncode.apply("hello world"), "hello%20world")
    }

    func testUrlDecode() {
        XCTAssertEqual(TextTransform.urlDecode.apply("hello%20world"), "hello world")
    }

    func testJsonFormat() {
        let input = "{\"b\":2,\"a\":1}"
        let result = TextTransform.jsonFormat.apply(input)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\n"))  // pretty printed
    }

    func testJsonFormatInvalid() {
        XCTAssertNil(TextTransform.jsonFormat.apply("not json"))
    }

    func testBase64Encode() {
        XCTAssertEqual(TextTransform.base64Encode.apply("hello"), "aGVsbG8=")
    }

    func testBase64Decode() {
        XCTAssertEqual(TextTransform.base64Decode.apply("aGVsbG8="), "hello")
    }

    func testBase64DecodeInvalid() {
        XCTAssertNil(TextTransform.base64Decode.apply("not-base64!!!"))
    }

    func testAllCasesHaveLocalizationKey() {
        for transform in TextTransform.allCases {
            XCTAssertTrue(transform.localizationKey.hasPrefix("transform."))
        }
    }
}
