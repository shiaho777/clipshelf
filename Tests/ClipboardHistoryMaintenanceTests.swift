import XCTest
@testable import ClipboardManager

final class ClipboardHistoryMaintenanceTests: XCTestCase {
    func testWipePayloadClearsSensitiveFields() {
        var item = ClipboardItem(content: "secret", rtfData: Data([1, 2, 3]), type: .text, isSensitive: true)
        item.imageData = Data([9, 9])
        ClipboardHistoryMaintenance.wipePayload(&item)
        XCTAssertEqual(item.content.utf8.count, "secret".utf8.count)
        XCTAssertTrue(item.content.utf8.allSatisfy { $0 == 0 })
        XCTAssertNil(item.imageData)
        XCTAssertNil(item.rtfData)
    }

    func testExpiredItemsFilter() {
        let now = Date()
        let expired = ClipboardItem(content: "old", type: .text, expiresAt: now.addingTimeInterval(-1))
        let fresh = ClipboardItem(content: "new", type: .text, expiresAt: now.addingTimeInterval(60))
        let none = ClipboardItem(content: "none", type: .text)
        let result = ClipboardHistoryMaintenance.expiredItems(in: [expired, fresh, none], now: now)
        XCTAssertEqual(result.map(\.content), ["old"])
    }

    func testAutoCleanupCutoffAndCandidates() {
        let now = Date()
        XCTAssertNil(ClipboardHistoryMaintenance.autoCleanupCutoff(intervalDays: 0, now: now))
        let cutoff = ClipboardHistoryMaintenance.autoCleanupCutoff(intervalDays: 7, now: now)
        XCTAssertNotNil(cutoff)
        let old = ClipboardItem(content: "old", type: .text, timestamp: now.addingTimeInterval(-10 * 86400))
        let pinnedOld = ClipboardItem(content: "pin", type: .text, timestamp: now.addingTimeInterval(-10 * 86400), isPinned: true)
        let fresh = ClipboardItem(content: "fresh", type: .text, timestamp: now)
        let result = ClipboardHistoryMaintenance.autoCleanupCandidates(
            in: [old, pinnedOld, fresh],
            olderThan: cutoff!
        )
        XCTAssertEqual(result.map(\.content), ["old"])
    }

    func testUnpinnedAndOCRCandidates() {
        let pinned = ClipboardItem(content: "p", type: .text, isPinned: true)
        let unpinned = ClipboardItem(content: "u", type: .text)
        XCTAssertEqual(ClipboardHistoryMaintenance.unpinnedItems(in: [pinned, unpinned]).map(\.content), ["u"])

        let imageNoOCR = ClipboardItem(content: "", type: .image)
        var imageWithOCR = ClipboardItem(content: "", type: .image)
        imageWithOCR.ocrText = "x"
        let text = ClipboardItem(content: "t", type: .text)
        let ids = ClipboardHistoryMaintenance.ocrMigrationCandidateIDs(
            in: [text, imageWithOCR, imageNoOCR],
            limit: 5
        )
        XCTAssertEqual(ids, [imageNoOCR.id])
    }

    func testAdditionalStoreIDs() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let extra = ClipboardHistoryMaintenance.additionalStoreIDs([a, b, c], excluding: [a, c])
        XCTAssertEqual(extra, [b])
    }

    func testPlanClearUnpinned() {
        let pinned = ClipboardItem(content: "p", type: .text, isPinned: true)
        let a = ClipboardItem(content: "a", type: .text)
        let b = ClipboardItem(content: "b", type: .text)
        let plan = ClipboardHistoryMaintenance.planClearUnpinned(items: [pinned, a, b])
        XCTAssertEqual(plan.remainingItems.map(\.content), ["p"])
        XCTAssertEqual(Set(plan.removedItems.map(\.content)), ["a", "b"])
        XCTAssertEqual(plan.removedIDs, Set(plan.removedItems.map(\.id)))
    }
}
