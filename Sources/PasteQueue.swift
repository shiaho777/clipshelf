import Foundation
import SwiftUI

@MainActor
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var queue: [ClipboardItem] = []
    private var headIndex: Int = 0

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

    func enqueue(_ item: ClipboardItem) {
        queue.append(item)
        NotificationCenter.default.post(name: .pasteQueueChanged, object: nil)
    }

    func dequeueNext() -> ClipboardItem? {
        guard headIndex < queue.count else { return nil }
        objectWillChange.send()
        let item = queue[headIndex]
        headIndex += 1
        if headIndex >= 16, headIndex * 2 >= queue.count {
            queue.removeFirst(headIndex)
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
