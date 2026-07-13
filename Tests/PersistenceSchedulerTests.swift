import XCTest
@testable import ClipboardManager

final class PersistenceSchedulerTests: XCTestCase {

    // MARK: - testScheduleFiresAfterDebounce

    func testScheduleFiresAfterDebounce() {
        let exp = expectation(description: "persist called")
        var persistedValue: Int?
        let scheduler = PersistenceScheduler<Int>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 0.1
        ) { value in
            persistedValue = value
            exp.fulfill()
        }
        scheduler.schedule(42)
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(persistedValue, 42)
    }

    // MARK: - testScheduleCancelsPrevious

    func testScheduleCancelsPrevious() {
        let exp = expectation(description: "persist called once")
        var callCount = 0
        var lastValue: String?
        let scheduler = PersistenceScheduler<String>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 0.15
        ) { value in
            callCount += 1
            lastValue = value
            exp.fulfill()
        }
        scheduler.schedule("first")
        // Schedule again quickly — should cancel the first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scheduler.schedule("second")
        }
        wait(for: [exp], timeout: 1.0)
        // Wait a bit more to make sure no extra call fires
        let noExtra = expectation(description: "no extra call")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { noExtra.fulfill() }
        wait(for: [noExtra], timeout: 1.0)
        XCTAssertEqual(callCount, 1, "Only the last scheduled value should persist")
        XCTAssertEqual(lastValue, "second")
    }

    // MARK: - testFlushExecutesImmediately

    func testFlushExecutesImmediately() {
        var persistedValue: Int?
        let scheduler = PersistenceScheduler<Int>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 10.0 // Very long debounce — should not matter for flush
        ) { value in
            persistedValue = value
        }
        scheduler.flush(99)
        // flush is synchronous — value should be set immediately
        XCTAssertEqual(persistedValue, 99)
    }

    // MARK: - testCancelPreventsPersist

    func testCancelPreventsPersist() {
        var called = false
        let scheduler = PersistenceScheduler<Int>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 0.1
        ) { _ in
            called = true
        }
        scheduler.schedule(1)
        scheduler.cancel()
        let exp = expectation(description: "wait for debounce to pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(called, "Persist should not be called after cancel")
    }

    // MARK: - testHasPending

    func testHasPending() {
        let scheduler = PersistenceScheduler<Int>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 5.0
        ) { _ in }
        XCTAssertFalse(scheduler.hasPending)
        scheduler.schedule(1)
        XCTAssertTrue(scheduler.hasPending)
        scheduler.cancel()
        XCTAssertFalse(scheduler.hasPending)
    }

    func testHasPendingAfterFlush() {
        let scheduler = PersistenceScheduler<Int>(
            queue: DispatchQueue(label: "test.persist"),
            debounce: 5.0
        ) { _ in }
        scheduler.schedule(1)
        XCTAssertTrue(scheduler.hasPending)
        scheduler.flush(1)
        XCTAssertFalse(scheduler.hasPending)
    }
}
