import XCTest
@testable import ClipShelf

final class OCRCandidateFilterTests: XCTestCase {

    func testLowConfidenceObservationsAreDropped() {
        let candidates = [
            (string: "place is a shelter", confidence: Float(0.95)),
            (string: "e13·", confidence: Float(0.2)),
            (string: "#Mcdull", confidence: Float(0.88)),
            (string: "+J", confidence: Float(0.1)),
        ]
        XCTAssertEqual(
            OCRCandidateFilter.joinedText(from: candidates),
            "place is a shelter #Mcdull"
        )
    }

    func testAllLowConfidenceReturnsNil() {
        let candidates = [
            (string: "e13·", confidence: Float(0.3)),
            (string: "140₿", confidence: Float(0.1)),
        ]
        XCTAssertNil(OCRCandidateFilter.joinedText(from: candidates))
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(OCRCandidateFilter.joinedText(from: []))
    }

    func testExactlyAtThresholdIsKept() {
        let candidates = [(string: "word", confidence: OCRCandidateFilter.minimumConfidence)]
        XCTAssertEqual(OCRCandidateFilter.joinedText(from: candidates), "word")
    }

    func testJustBelowThresholdIsDropped() {
        let candidates = [(string: "word", confidence: OCRCandidateFilter.minimumConfidence - 0.01)]
        XCTAssertNil(OCRCandidateFilter.joinedText(from: candidates))
    }

    func testClearTextPassesThroughUnchanged() {
        let candidates = [
            (string: "Gemini", confidence: Float(0.99)),
            (string: "GitHub Z.ai", confidence: Float(0.97)),
            (string: "Free AI Chat", confidence: Float(0.93)),
        ]
        XCTAssertEqual(
            OCRCandidateFilter.joinedText(from: candidates),
            "Gemini GitHub Z.ai Free AI Chat"
        )
    }

    func testWhitespaceOnlyAfterFilteringReturnsNil() {
        let candidates = [(string: "   ", confidence: Float(0.9))]
        XCTAssertNil(OCRCandidateFilter.joinedText(from: candidates))
    }
}
