import Foundation

final class PersistenceScheduler<T> {
    private let queue: DispatchQueue
    private let debounce: TimeInterval
    private let persist: (T) -> Void
    private let lock = NSLock()
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
        lock.lock()
        pendingWorkItem?.cancel()
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, let item = workItem, !item.isCancelled else { return }
            self.lock.withLock {
                if self.pendingWorkItem === item {
                    self.pendingWorkItem = nil
                }
            }
            self.persist(value)
        }
        guard let item = workItem else {
            lock.unlock()
            return
        }
        pendingWorkItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    func flush(_ value: T) {
        lock.withLock {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
        }
        let group = DispatchGroup()
        group.enter()
        queue.async { [persist] in
            persist(value)
            group.leave()
        }
        group.wait()
    }

    func cancel() {
        lock.withLock {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
        }
    }

    var hasPending: Bool {
        lock.withLock { pendingWorkItem != nil }
    }
}
