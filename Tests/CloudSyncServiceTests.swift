import XCTest
@testable import ClipShelf

final class CloudSyncServiceTests: XCTestCase {
    func testDefaultContainerIdentifier() {
        XCTAssertEqual(CloudSyncService.defaultContainerIdentifier, "iCloud.com.nicebro.ClipShelf")
    }

    func testReadinessReadyFlag() {
        XCTAssertTrue(CloudSyncReadiness.ready.isReady)
        XCTAssertFalse(CloudSyncReadiness.missingEntitlement.isReady)
        XCTAssertFalse(CloudSyncReadiness.checking.isReady)
        XCTAssertFalse(CloudSyncReadiness.restricted.isReady)
    }
}
