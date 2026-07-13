import XCTest
@testable import ClipboardManager

final class ContentDetectorTests: XCTestCase {

    // MARK: - HEX Color Detection

    func testHex6Digit() {
        let result = ContentDetector.analyze("#FF0000")
        XCTAssertNotNil(result.color)
        XCTAssertEqual(result.colorString(format: .hex), "#FF0000")
    }

    func testHex3Digit() {
        let result = ContentDetector.analyze("#FFF")
        XCTAssertNotNil(result.color)
        XCTAssertEqual(result.colorString(format: .hex), "#FFFFFF")
    }

    func testHex8DigitWithAlpha() {
        let result = ContentDetector.analyze("#FF000080")
        XCTAssertNotNil(result.color)
    }

    func testHexInvalid() {
        XCTAssertNil(ContentDetector.analyze("#GGG").color)
        XCTAssertNil(ContentDetector.analyze("#12").color)
        XCTAssertNil(ContentDetector.analyze("not a color").color)
    }

    // MARK: - RGB Color Detection

    func testRGB() {
        let result = ContentDetector.analyze("rgb(255, 0, 0)")
        XCTAssertNotNil(result.color)
        XCTAssertEqual(result.colorString(format: .hex), "#FF0000")
    }

    func testRGBA() {
        let result = ContentDetector.analyze("rgba(0, 0, 0, 0.5)")
        XCTAssertNotNil(result.color)
        XCTAssertEqual(result.colorString(format: .hex), "#000000")
    }

    func testRGBClampedValues() {
        // Values > 255 should be clamped
        let result = ContentDetector.analyze("rgb(300, 300, 300)")
        XCTAssertNotNil(result.color)
        XCTAssertEqual(result.colorString(format: .hex), "#FFFFFF")
    }

    // MARK: - HSL Output

    func testHSLOutputForPureRed() {
        let result = ContentDetector.analyze("#FF0000")
        let hsl = result.colorString(format: .hsl)
        XCTAssertNotNil(hsl)
        XCTAssertTrue(hsl!.hasPrefix("hsl(0°"))
        XCTAssertTrue(hsl!.contains("100%"))
    }

    func testHSLOutputForGray() {
        let result = ContentDetector.analyze("#808080")
        let hsl = result.colorString(format: .hsl)
        XCTAssertNotNil(hsl)
        XCTAssertTrue(hsl!.hasPrefix("hsl(0°"))
        XCTAssertTrue(hsl!.contains("0%"))  // saturation = 0
    }

    // MARK: - URL Detection

    func testHTTPSURL() {
        let result = ContentDetector.analyze("https://example.com")
        XCTAssertTrue(result.isURL)
        XCTAssertEqual(result.url?.host, "example.com")
    }

    func testHTTPURL() {
        let result = ContentDetector.analyze("http://example.com/path?q=1")
        XCTAssertTrue(result.isURL)
    }

    func testNonURL() {
        XCTAssertFalse(ContentDetector.analyze("just some text").isURL)
        XCTAssertFalse(ContentDetector.analyze("ftp://example.com").isURL)
        XCTAssertFalse(ContentDetector.analyze("example.com").isURL)
    }

    func testURLWithWhitespace() {
        let result = ContentDetector.analyze("  https://example.com  ")
        XCTAssertTrue(result.isURL)
    }

    // MARK: - File Path Detection

    func testAbsolutePathExists() {
        let result = ContentDetector.analyze("/tmp")
        XCTAssertTrue(result.isFilePath)
        XCTAssertEqual(result.filePath, "/tmp")
    }

    func testTildePathExists() {
        let result = ContentDetector.analyze("~/Desktop")
        XCTAssertTrue(result.isFilePath)
    }

    func testNonExistentPath() {
        let result = ContentDetector.analyze("/this/path/does/not/exist/at/all")
        XCTAssertFalse(result.isFilePath)
    }

    func testFileURLScheme() {
        let result = ContentDetector.analyze("file:///tmp")
        XCTAssertTrue(result.isFilePath)
    }

    func testNonPathText() {
        XCTAssertFalse(ContentDetector.analyze("hello world").isFilePath)
    }

    // MARK: - Cache Consistency

    func testAnalyzeCacheReturnsSameResult() {
        let text = "https://cached-test.example.com"
        let first = ContentDetector.analyze(text)
        let second = ContentDetector.analyze(text)
        XCTAssertEqual(first.url, second.url)
        XCTAssertEqual(first.trimmedText, second.trimmedText)
    }

    // MARK: - Empty / Image Bypass

    func testEmptyStringReturnsEmpty() {
        let result = ContentDetector.analyze("")
        XCTAssertNil(result.color)
        XCTAssertNil(result.url)
        XCTAssertNil(result.filePath)
    }

    func testStaticEmptyConstant() {
        let empty = ContentDetectionResult.empty
        XCTAssertFalse(empty.isURL)
        XCTAssertFalse(empty.isFilePath)
        XCTAssertNil(empty.color)
    }
}
