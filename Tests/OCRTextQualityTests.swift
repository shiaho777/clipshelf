import XCTest
@testable import ClipShelf

final class OCRTextQualityTests: XCTestCase {

    // MARK: - Rejection cases (fall back to "[Image]")

    /// Real capture from a music-player screenshot: stylized fonts OCR into
    /// glyph soup; only the track timestamps survive the token filter, which
    /// is below the 3-word threshold.
    func testStylizedMusicPlayerNoiseIsRejected() {
        let ocr = "e13· = 4 140₿ +J + HIfE*> 00:00 / 04:21 1 - 7 LO…"
        XCTAssertNil(OCRTextQuality.usableText(from: ocr))
    }

    func testPureSymbolSoupIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: "» ♥ ✓ ✈ ‹ ›"))
    }

    func testSingleDigitTokensDoNotCountAsWords() {
        // "1", "4", "7" are lone digits with no letter and fewer than two
        // digits, so they must not count toward the word threshold.
        XCTAssertNil(OCRTextQuality.usableText(from: "1 4 7"))
    }

    func testEmptyAndNilInputIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: nil))
        XCTAssertNil(OCRTextQuality.usableText(from: ""))
        XCTAssertNil(OCRTextQuality.usableText(from: "   \n  "))
    }

    // MARK: - Acceptance cases (OCR line is shown)

    /// Same screenshot family as the rejection case, but the song title is
    /// real text, so enough valid words survive the filter.
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

    // MARK: - Boundary behavior

    func testExactlyAtThresholdIsKept() {
        XCTAssertNotNil(OCRTextQuality.usableText(from: "one two three"))
    }

    func testJustBelowThresholdIsRejected() {
        XCTAssertNil(OCRTextQuality.usableText(from: "one two"))
    }

    /// A lone CJK string with no whitespace counts as a single token; dense
    /// single-fragment captions therefore still fall back to the plain label.
    func testSingleUnbrokenCJKStringIsBelowThreshold() {
        XCTAssertNil(OCRTextQuality.usableText(from: "你是一名资深图形程序员"))
    }

    /// A token like "4" or "7" is not a word, but multi-digit values such as
    /// timestamps and speeds are treated as real information.
    func testMultiDigitNumbersCountAsWords() {
        XCTAssertNotNil(OCRTextQuality.usableText(from: "514 17:30 55"))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(OCRTextQuality.usableText(from: "  hello world again \n"), "hello world again")
    }
}
