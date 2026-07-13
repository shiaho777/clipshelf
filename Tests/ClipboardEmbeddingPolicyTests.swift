import XCTest
@testable import ClipShelf

final class ClipboardEmbeddingPolicyTests: XCTestCase {
    func testEligibilityFiltersImageEmptyAndSensitive() {
        XCTAssertTrue(ClipboardEmbeddingPolicy.isEligible(ClipboardItem(content: "ok", type: .text)))
        XCTAssertTrue(ClipboardEmbeddingPolicy.isEligible(ClipboardItem(content: "ok", type: .richText)))
        XCTAssertFalse(ClipboardEmbeddingPolicy.isEligible(ClipboardItem(content: "", type: .text)))
        XCTAssertFalse(ClipboardEmbeddingPolicy.isEligible(ClipboardItem(content: "x", type: .image)))
        XCTAssertFalse(ClipboardEmbeddingPolicy.isEligible(ClipboardItem(content: "secret", type: .text, isSensitive: true)))
    }

    func testStartupWarmItemsRespectsLimit() {
        let items = (0..<10).map { ClipboardItem(content: "\($0)", type: .text) }
        XCTAssertEqual(ClipboardEmbeddingPolicy.startupWarmItems(from: items, limit: 3).map(\.content), ["0", "1", "2"])
        XCTAssertEqual(ClipboardEmbeddingPolicy.startupWarmItems(from: items, limit: 0), [])
        XCTAssertEqual(ClipboardEmbeddingPolicy.startupWarmItems(from: items, limit: 100).count, 10)
    }
}
