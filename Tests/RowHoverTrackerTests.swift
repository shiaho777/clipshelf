import XCTest
@testable import ClipShelf

final class RowHoverTrackerTests: XCTestCase {

    @MainActor
    func testSetAndClear() {
        let id = UUID()
        RowHoverTracker.shared.set(id)
        XCTAssertEqual(RowHoverTracker.shared.itemID, id)

        RowHoverTracker.shared.set(nil)
        XCTAssertNil(RowHoverTracker.shared.itemID)
    }

    @MainActor
    func testSetReplacesPreviousRow() {
        let first = UUID()
        let second = UUID()
        RowHoverTracker.shared.set(first)
        RowHoverTracker.shared.set(second)
        XCTAssertEqual(RowHoverTracker.shared.itemID, second)

        RowHoverTracker.shared.set(nil)
    }
}
