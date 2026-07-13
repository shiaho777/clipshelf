import XCTest
@testable import ClipShelf

@MainActor
final class PasteQueueTests: XCTestCase {
    var queue: PasteQueue!
    
    override func setUp() {
        super.setUp()
        queue = PasteQueue()
    }
    
    func testInitialState() {
        XCTAssertTrue(queue.queue.isEmpty)
        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(queue.remaining, 0)
    }
    
    func testEnqueueSingleItem() {
        let item = ClipboardItem(content: "hello")
        queue.enqueue([item])
        XCTAssertTrue(queue.isActive)
        XCTAssertEqual(queue.remaining, 1)
    }
    
    func testEnqueueMultipleItems() {
        let items = (1...3).map { ClipboardItem(content: "item \($0)") }
        queue.enqueue(items)
        XCTAssertEqual(queue.remaining, 3)
    }
    
    func testDequeueOrder() {
        let items = ["first", "second", "third"].map { ClipboardItem(content: $0) }
        queue.enqueue(items)
        
        XCTAssertEqual(queue.dequeueNext()?.content, "first")
        XCTAssertEqual(queue.remaining, 2)
        XCTAssertEqual(queue.dequeueNext()?.content, "second")
        XCTAssertEqual(queue.remaining, 1)
        XCTAssertEqual(queue.dequeueNext()?.content, "third")
        XCTAssertEqual(queue.remaining, 0)
        XCTAssertFalse(queue.isActive)
    }
    
    func testDequeueFromEmptyReturnsNil() {
        XCTAssertNil(queue.dequeueNext())
    }
    
    func testClear() {
        let items = (1...5).map { ClipboardItem(content: "item \($0)") }
        queue.enqueue(items)
        XCTAssertEqual(queue.remaining, 5)
        
        queue.clear()
        XCTAssertTrue(queue.queue.isEmpty)
        XCTAssertFalse(queue.isActive)
    }
    
    func testMultipleEnqueues() {
        queue.enqueue([ClipboardItem(content: "a")])
        queue.enqueue([ClipboardItem(content: "b"), ClipboardItem(content: "c")])
        XCTAssertEqual(queue.remaining, 3)
        XCTAssertEqual(queue.dequeueNext()?.content, "a")
        XCTAssertEqual(queue.dequeueNext()?.content, "b")
        XCTAssertEqual(queue.dequeueNext()?.content, "c")
    }

    func testPendingItemsPrefixHonorsHeadIndexAndLimit() {
        let items = (1...5).map { ClipboardItem(content: "item \($0)") }
        queue.enqueue(items)
        _ = queue.dequeueNext()
        _ = queue.dequeueNext()

        let prefix = queue.pendingItemsPrefix(2)

        XCTAssertEqual(prefix.map(\.content), ["item 3", "item 4"])
        XCTAssertEqual(queue.remaining, 3)
    }
}
