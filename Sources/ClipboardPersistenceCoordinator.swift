import Foundation
import os

final class ClipboardPersistenceCoordinator {
    private let historyStore: ClipboardHistoryStore
    private let logger: Logger
    private let incrementalQueue: DispatchQueue
    private let snapshotScheduler: PersistenceScheduler<[ClipboardItem]>
    private let usageSnapshotScheduler: PersistenceScheduler<[ClipboardItem]>
    private var pendingUseCountPersistByID: [UUID: Int] = [:]
    private var pendingUseCountFlushWork: DispatchWorkItem?
    private let useCountDebounce: TimeInterval
    private let onDeletedIDs: ((Set<UUID>) -> Void)?

    init(
        historyStore: ClipboardHistoryStore,
        logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "Persistence"),
        useCountDebounce: TimeInterval = 0.5,
        snapshotDebounce: TimeInterval = 0.2,
        usageSnapshotDebounce: TimeInterval = 1.5,
        onDeletedIDs: ((Set<UUID>) -> Void)? = nil
    ) {
        self.historyStore = historyStore
        self.logger = logger
        self.useCountDebounce = useCountDebounce
        self.onDeletedIDs = onDeletedIDs
        let queue = DispatchQueue(label: "ClipShelf.persistence", qos: .utility)
        self.incrementalQueue = DispatchQueue(label: "ClipShelf.incrementalPersistence", qos: .utility)
        let store = historyStore
        let log = logger
        let persistBlock: ([ClipboardItem]) -> Void = { items in
            do { _ = try store.saveItems(items) }
            catch { log.error("Failed to save clipboard history: \(error.localizedDescription)") }
        }
        self.snapshotScheduler = PersistenceScheduler(queue: queue, debounce: snapshotDebounce, persist: persistBlock)
        self.usageSnapshotScheduler = PersistenceScheduler(queue: queue, debounce: usageSnapshotDebounce, persist: persistBlock)
    }

    func upsert(_ item: ClipboardItem) {
        let store = historyStore
        let log = logger
        incrementalQueue.async {
            do { _ = try store.upsertItem(item) }
            catch { log.error("Failed to upsert clipboard item: \(error.localizedDescription)") }
        }
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if let onDeletedIDs {
            DispatchQueue.main.async {
                onDeletedIDs(ids)
            }
        }
        let store = historyStore
        let log = logger
        incrementalQueue.async {
            do { _ = try store.deleteItems(ids: ids) }
            catch { log.error("Failed to delete clipboard items: \(error.localizedDescription)") }
        }
    }

    func scheduleUseCount(id: UUID, useCount: Int) {
        pendingUseCountPersistByID[id] = useCount
        pendingUseCountFlushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushUseCounts()
        }
        pendingUseCountFlushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + useCountDebounce, execute: work)
    }

    func flushUseCounts() {
        let pending = pendingUseCountPersistByID
        pendingUseCountPersistByID.removeAll(keepingCapacity: true)
        pendingUseCountFlushWork = nil
        guard !pending.isEmpty else { return }
        let store = historyStore
        let log = logger
        incrementalQueue.async {
            do { _ = try store.updateUseCounts(pending) }
            catch { log.error("Failed to update clipboard item use counts: \(error.localizedDescription)") }
        }
    }

    func scheduleSnapshot(_ items: [ClipboardItem], immediately: Bool) {
        if immediately {
            snapshotScheduler.flush(items)
        } else {
            usageSnapshotScheduler.cancel()
            snapshotScheduler.schedule(items)
        }
    }

    func scheduleUsageSnapshot(_ items: [ClipboardItem]) {
        guard !snapshotScheduler.hasPending else { return }
        usageSnapshotScheduler.schedule(items)
    }

    func flushAll(items: [ClipboardItem]) {
        let group = DispatchGroup()
        pendingUseCountFlushWork?.cancel()
        flushUseCounts()
        group.enter()
        incrementalQueue.async { group.leave() }
        group.wait()
        snapshotScheduler.flush(items)
        usageSnapshotScheduler.cancel()
    }

    func waitForIncrementalIdle() {
        let group = DispatchGroup()
        group.enter()
        incrementalQueue.async { group.leave() }
        group.wait()
    }
}
