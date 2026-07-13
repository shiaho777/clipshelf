import Foundation
import SwiftUI

@MainActor
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    /// Backing storage. Consumed entries stay until `compact()` reclaims them.
    @Published private(set) var queue: [ClipboardItem] = []
    /// Index of the next item to return; makes `dequeueNext` O(1).
    private var headIndex: Int = 0

    /// When `stackMode` is on, every captured clipboard item is automatically
    /// enqueued instead of (or in addition to) being stored in history.
    /// This mirrors the CleanClip / OneClip "paste stack" workflow:
    /// turn it on, copy several things, then paste them one-by-one.
    @Published var stackMode: Bool = false {
        didSet {
            guard oldValue != stackMode else { return }
            NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
        }
    }

    var isActive: Bool { headIndex < queue.count }
    var remaining: Int { queue.count - headIndex }

    func enqueue(_ items: [ClipboardItem]) {
        queue.append(contentsOf: items)
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
    }

    /// Enqueue a single item (used by stack mode when a new copy is captured).
    func enqueue(_ item: ClipboardItem) {
        queue.append(item)
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
    }

    func dequeueNext() -> ClipboardItem? {
        guard headIndex < queue.count else { return nil }
        // Notify observers before mutating so SwiftUI sees one coherent update.
        objectWillChange.send()
        let item = queue[headIndex]
        headIndex += 1
        // Compact when ≥16 entries have been consumed AND they represent ≥50 % of
        // the array — avoids unbounded memory growth for large sequential pastes.
        if headIndex >= 16, headIndex * 2 >= queue.count {
            queue.removeFirst(headIndex)   // @Published fires objectWillChange again – fine
            headIndex = 0
        }
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
        return item
    }

    func clear() {
        queue.removeAll()
        headIndex = 0
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
    }

    /// Items not yet dequeued, in order.
    var pendingItems: [ClipboardItem] {
        guard headIndex < queue.count else { return [] }
        return Array(queue[headIndex...])
    }

    func pendingItemsPrefix(_ count: Int) -> [ClipboardItem] {
        let boundedCount = max(0, min(count, remaining))
        guard boundedCount > 0 else { return [] }
        let end = headIndex + boundedCount
        return Array(queue[headIndex..<end])
    }

    /// Remove a pending item by its index within `pendingItems` (0 = next to be pasted).
    func remove(at pendingIndex: Int) {
        let actual = headIndex + pendingIndex
        guard actual < queue.count else { return }
        objectWillChange.send()
        queue.remove(at: actual)
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
    }
}

extension Notification.Name {
    static let pasteQueueChanged = Notification.Name("PasteQueueChanged")
}
