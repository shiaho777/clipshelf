import XCTest
@testable import ClipShelf

final class ClipboardHistoryQueriesTests: XCTestCase {
    func testRecentContentsRespectsLimit() {
        let items = (0..<5).map { ClipboardItem(content: "\($0)", type: .text) }
        XCTAssertEqual(ClipboardHistoryQueries.recentContents(from: items, limit: 3), ["0", "1", "2"])
        XCTAssertEqual(ClipboardHistoryQueries.recentContents(from: items, limit: 0), [])
        XCTAssertEqual(ClipboardHistoryQueries.recentContents(from: items, limit: 100), items.map(\.content))
    }

    func testContentsBySourceBundleID() {
        let items = [
            ClipboardItem(content: "a", type: .text, sourceBundleID: "com.a"),
            ClipboardItem(content: "b", type: .text, sourceBundleID: "com.b"),
            ClipboardItem(content: "c", type: .text, sourceBundleID: "com.a")
        ]
        XCTAssertEqual(
            ClipboardHistoryQueries.contents(from: items, sourceBundleID: "com.a", limit: 10),
            ["a", "c"]
        )
        XCTAssertEqual(
            ClipboardHistoryQueries.contents(from: items, sourceBundleID: "com.a", limit: 1),
            ["a"]
        )
    }
}
