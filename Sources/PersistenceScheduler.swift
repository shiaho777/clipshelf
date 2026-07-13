import Foundation

final class PersistenceScheduler<T> {
    private let queue: DispatchQueue
    private let debounce: TimeInterval
    private let persist: (T) -> Void
    private var pendingWorkItem: DispatchWorkItem?

    init(
        queue: DispatchQueue = DispatchQueue(label: "PersistenceScheduler", qos: .utility),
        debounce: TimeInterval = 0.2,
        persist: @escaping (T) -> Void
    ) {
        self.queue = queue
        self.debounce = debounce
        self.persist = persist
    }

    func schedule(_ value: T) {
        pendingWorkItem?.cancel()
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, let workItem, !workItem.isCancelled else { return }
            if self.pendingWorkItem === workItem {
                self.pendingWorkItem = nil
            }
            self.persist(value)
        }
        guard let workItem else { return }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounce, execute: workItem)
    }

    func flush(_ value: T) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        // Use DispatchGroup instead of queue.sync to avoid deadlock when
        // flush() is called from the main thread while the queue targets main.
        let group = DispatchGroup()
        group.enter()
        queue.async { [persist] in
            persist(value)
            group.leave()
        }
        group.wait()
    }

    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    var hasPending: Bool { pendingWorkItem != nil }
}
