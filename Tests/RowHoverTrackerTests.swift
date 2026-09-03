import XCTest
@testable import ClipShelf

/// The history list consults a plain tracker (not SwiftUI @State) for the
/// hovered row, so pointer crossings during a scroll don't re-render the list.
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

        // Leave clean state for other tests / the running app.
        RowHoverTracker.shared.set(nil)
    }
}
