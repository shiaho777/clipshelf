import XCTest
@testable import ClipShelf

final class ClipboardHistoryOrderingTests: XCTestCase {
    func testReorderedByPinStateMovesPinnedFirst() {
        let a = ClipboardItem(content: "a", type: .text, isPinned: false)
        let b = ClipboardItem(content: "b", type: .text, isPinned: true)
        let c = ClipboardItem(content: "c", type: .text, isPinned: false)
        let result = ClipboardHistoryOrdering.reorderedByPinState([a, b, c])
        XCTAssertEqual(result.pinnedCount, 1)
        XCTAssertEqual(result.items.map(\.content), ["b", "a", "c"])
    }

    func testEnforceHotWindowKeepsPinnedAndNewestUnpinned() {
        let pinned = ClipboardItem(content: "pin", type: .text, timestamp: Date().addingTimeInterval(-100), isPinned: true)
        let newer = ClipboardItem(content: "new", type: .text, timestamp: Date())
        let older = ClipboardItem(content: "old", type: .text, timestamp: Date().addingTimeInterval(-50))
        let items = [pinned, newer, older]
        let enforced = ClipboardHistoryOrdering.enforceHotWindow(items, hotWindowCount: 2)
        XCTAssertEqual(enforced?.map(\.content), ["pin", "new"])
    }

    func testEnforceHotWindowNoopWhenWithinLimit() {
        let items = [
            ClipboardItem(content: "a", type: .text),
            ClipboardItem(content: "b", type: .text)
        ]
        XCTAssertNil(ClipboardHistoryOrdering.enforceHotWindow(items, hotWindowCount: 5))
    }

    func testMergeByTimestampDescending() {
        let now = Date()
        let existing = [
            ClipboardItem(content: "e1", type: .text, timestamp: now.addingTimeInterval(-10)),
            ClipboardItem(content: "e2", type: .text, timestamp: now.addingTimeInterval(-30))
        ]
        let incoming = [
            ClipboardItem(content: "i1", type: .text, timestamp: now.addingTimeInterval(-5)),
            ClipboardItem(content: "i2", type: .text, timestamp: now.addingTimeInterval(-20))
        ]
        let merged = ClipboardHistoryOrdering.mergeByTimestampDescending(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.map(\.content), ["i1", "e1", "i2", "e2"])
    }

    func testTrimUnpinnedInMemory() {
        let items = (0..<5).map { ClipboardItem(content: "\($0)", type: .text) }
        let result = ClipboardHistoryOrdering.trimUnpinnedInMemory(items, maxHistoryCount: 3, pinnedCount: 0)
        XCTAssertEqual(result?.items.map(\.content), ["0", "1", "2"])
        XCTAssertEqual(result?.removed.map(\.content), ["3", "4"])
    }

    func testMergeFetchedKeepsPinnedAndUnpinnedLanes() {
        let now = Date()
        let existing = [
            ClipboardItem(content: "pin-old", type: .text, timestamp: now.addingTimeInterval(-30), isPinned: true),
            ClipboardItem(content: "u-new", type: .text, timestamp: now.addingTimeInterval(-10)),
            ClipboardItem(content: "u-old", type: .text, timestamp: now.addingTimeInterval(-40))
        ]
        let incoming = [
            ClipboardItem(content: "pin-new", type: .text, timestamp: now.addingTimeInterval(-5), isPinned: true),
            ClipboardItem(content: "u-mid", type: .text, timestamp: now.addingTimeInterval(-20))
        ]
        let merged = ClipboardHistoryOrdering.mergeFetched(
            existing: existing,
            pinnedCount: 1,
            incoming: incoming
        )
        XCTAssertEqual(merged.map(\.content), ["pin-new", "pin-old", "u-new", "u-mid", "u-old"])
    }

    func testReorderedAfterTogglingPinMovesItemToPinnedHead() {
        let a = ClipboardItem(content: "a", type: .text, isPinned: false)
        let b = ClipboardItem(content: "b", type: .text, isPinned: false)
        let result = ClipboardHistoryOrdering.reorderedAfterTogglingPin(items: [a, b], at: 1)
        XCTAssertEqual(result?.pinnedCount, 1)
        XCTAssertEqual(result?.items.map(\.content), ["b", "a"])
        XCTAssertTrue(result?.updated.isPinned == true)
        XCTAssertEqual(result?.updated.id, b.id)
    }

    func testReorderedAfterTogglingPinUnpinKeepsPinnedLane() {
        let pin = ClipboardItem(content: "pin", type: .text, isPinned: true)
        let other = ClipboardItem(content: "other", type: .text, isPinned: false)
        let result = ClipboardHistoryOrdering.reorderedAfterTogglingPin(items: [pin, other], at: 0)
        XCTAssertEqual(result?.pinnedCount, 0)
        XCTAssertEqual(result?.items.map(\.content), ["pin", "other"])
        XCTAssertFalse(result?.updated.isPinned == true)
    }

    func testMaxUnpinnedCapacity() {
        XCTAssertEqual(
            ClipboardHistoryOrdering.maxUnpinnedCapacity(maxHistoryCount: 10, pinnedCount: 3, itemCount: 8),
            7
        )
        XCTAssertEqual(
            ClipboardHistoryOrdering.maxUnpinnedCapacity(maxHistoryCount: 0, pinnedCount: 2, itemCount: 5),
            0
        )
        XCTAssertEqual(
            ClipboardHistoryOrdering.maxUnpinnedCapacity(maxHistoryCount: 5, pinnedCount: 9, itemCount: 4),
            1
        )
    }
}

    func testMovingItemReordersAndStampsTimestamps() {
        let now = Date()
        let a = ClipboardItem(id: UUID(), content: "a", type: .text, timestamp: now.addingTimeInterval(-3))
        let b = ClipboardItem(id: UUID(), content: "b", type: .text, timestamp: now.addingTimeInterval(-2))
        let c = ClipboardItem(id: UUID(), content: "c", type: .text, timestamp: now.addingTimeInterval(-1))
        let items = [c, b, a]
        let moved = ClipboardHistoryOrdering.movingItem(
            id: a.id,
            toDestinationID: c.id,
            in: items,
            placeBefore: true
        )
        XCTAssertEqual(moved?.map(\.content), ["a", "c", "b"])
        guard let moved else { return }
        XCTAssertGreaterThan(moved[0].timestamp, moved[1].timestamp)
        XCTAssertGreaterThan(moved[1].timestamp, moved[2].timestamp)
    }

    func testMovingPinnedItemStaysInPinnedLane() {
        let now = Date()
        let p1 = ClipboardItem(id: UUID(), content: "p1", type: .text, timestamp: now.addingTimeInterval(-1), isPinned: true)
        let p2 = ClipboardItem(id: UUID(), content: "p2", type: .text, timestamp: now.addingTimeInterval(-2), isPinned: true)
        let u1 = ClipboardItem(id: UUID(), content: "u1", type: .text, timestamp: now.addingTimeInterval(-3))
        let moved = ClipboardHistoryOrdering.movingItem(
            id: p2.id,
            toDestinationID: p1.id,
            in: [p1, p2, u1],
            placeBefore: true
        )
        XCTAssertEqual(moved?.map(\.content), ["p2", "p1", "u1"])
        XCTAssertTrue(moved?.prefix(2).allSatisfy(\.isPinned) == true)
    }
