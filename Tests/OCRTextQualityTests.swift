import XCTest
@testable import ClipShelf

final class OCRTextQualityTests: XCTestCase {

    func testStylizedMusicPlayerNoiseIsRejected() {
        let ocr = "e13· = 4 140₿ +J + HIfE*> 00:00 / 04:21 1 - 7 LO…"
        XCTAssertNil(OCRTextQuality.usableText(from: ocr))
    }

    func testPureSymbolSoupIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: "» ♥ ✓ ✈ ‹ ›"))
    }

    func testSingleDigitTokensDoNotCountAsWords() {
        XCTAssertNil(OCRTextQuality.usableText(from: "1 4 7"))
    }

    func testEmptyAndNilInputIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: nil))
        XCTAssertNil(OCRTextQuality.usableText(from: ""))
        XCTAssertNil(OCRTextQuality.usableText(from: "   \n  "))
    }

    func testMusicScreenshotWithRealSongTitleIsKept() {
        let ocr = "· e13· 55 +J + place is a shelter #Mcdull *›‡ 00:…"
        XCTAssertEqual(OCRTextQuality.usableText(from: ocr), ocr)
    }

    func testGameHUDReadoutIsKept() {
        let ocr = "54 · km/h 514 17:30"
        XCTAssertEqual(OCRTextQuality.usableText(from: ocr), ocr)
    }

    func testBrowserTabTitleNoiseIsKept() {
        let ocr = "EQ → X1# * [a Gemini : GitHub Z.ai - Free AI Chat…"
        XCTAssertEqual(OCRTextQuality.usableText(from: ocr), ocr)
    }

    func testCleanSentenceIsKept() {
        let ocr = "Hello world from screenshot"
        XCTAssertEqual(OCRTextQuality.usableText(from: ocr), ocr)
    }

    func testChineseTokensAreValidWords() {
        let ocr = "设置 通用 快捷键"
        XCTAssertEqual(OCRTextQuality.usableText(from: ocr), ocr)
    }

    func testExactlyAtThresholdIsKept() {
        XCTAssertNotNil(OCRTextQuality.usableText(from: "one two three"))
    }

    func testJustBelowThresholdIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: "one two"))
    }

    func testSingleUnbrokenCJKStringIsBelowThreshold() {
        XCTAssertNil(OCRTextQuality.usableText(from: "你是一名资深图形程序员"))
    }

    func testMultiDigitNumbersCountAsWords() {
        XCTAssertNotNil(OCRTextQuality.usableText(from: "514 17:30 55"))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(OCRTextQuality.usableText(from: "  hello world again \n"), "hello world again")
    }
}
