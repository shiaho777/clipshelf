import XCTest
@testable import ClipShelf

final class PasteOutcomePolicyTests: XCTestCase {
    func testSecureInputBlocksEvenWhenFrontmost() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: true,
            secureInputEnabled: true,
            elapsed: 0.1,
            activationTimeout: 2.0,
            keystrokesAvailable: true
        )
        XCTAssertEqual(decision, .fail(.secureInput))
    }

    func testFrontmostMatchSendsKeystroke() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: true,
            secureInputEnabled: false,
            elapsed: 0.05,
            activationTimeout: 2.0,
            keystrokesAvailable: true
        )
        XCTAssertEqual(decision, .sendKeystroke)
    }

    func testFrontmostMatchWithoutKeystrokesFails() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: true,
            secureInputEnabled: false,
            elapsed: 0.05,
            activationTimeout: 2.0,
            keystrokesAvailable: false
        )
        XCTAssertEqual(decision, .fail(.keystrokeUnavailable))
    }

    func testNotFrontmostRetriesBeforeTimeout() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: false,
            secureInputEnabled: false,
            elapsed: 1.9,
            activationTimeout: 2.0,
            keystrokesAvailable: true
        )
        XCTAssertEqual(decision, .retryActivation)
    }

    func testNotFrontmostFailsAtTimeout() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: false,
            secureInputEnabled: false,
            elapsed: 2.0,
            activationTimeout: 2.0,
            keystrokesAvailable: true
        )
        XCTAssertEqual(decision, .fail(.activationTimeout))
    }

    func testSecureInputTakesPriorityOverTimeout() {
        let decision = PasteOutcomePolicy.decide(
            frontmostMatchesTarget: false,
            secureInputEnabled: true,
            elapsed: 5.0,
            activationTimeout: 2.0,
            keystrokesAvailable: true
        )
        XCTAssertEqual(decision, .fail(.secureInput))
    }
}

@MainActor
final class PasteQueueRequeueTests: XCTestCase {
    func testRequeueFrontRestoresDequeuedItem() {
        let queue = PasteQueue()
        let first = ClipboardItem(content: "first", type: .text)
        let second = ClipboardItem(content: "second", type: .text)
        queue.enqueue([first, second])
        let dequeued = queue.dequeueNext()
        XCTAssertEqual(dequeued?.id, first.id)
        XCTAssertEqual(queue.remaining, 1)
        queue.requeueFront(first)
        XCTAssertEqual(queue.remaining, 2)
        XCTAssertEqual(queue.pendingItems.map(\.id), [first.id, second.id])
    }

    func testRequeueFrontOnEmptyQueueMakesItemNext() {
        let queue = PasteQueue()
        let item = ClipboardItem(content: "solo", type: .text)
        queue.requeueFront(item)
        XCTAssertEqual(queue.remaining, 1)
        XCTAssertEqual(queue.dequeueNext()?.id, item.id)
        XCTAssertFalse(queue.isActive)
    }
}