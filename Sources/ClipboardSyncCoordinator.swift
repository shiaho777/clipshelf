import Foundation
import os

/// Coordinates iCloud sync: handles CloudSyncDelegate and upload debouncing.
/// Extracted from ClipboardManager to reduce its responsibilities.
@MainActor
final class ClipboardSyncCoordinator: CloudSyncDelegate {
    private lazy var cloudSync: CloudSyncService = CloudSyncService.shared
    private var uploadDebounceWork: DispatchWorkItem?
    private var pendingUploadItems: [UUID: ClipboardItem] = [:]
    private var pendingDeleteIDs: Set<UUID> = []
    private let isEnabled: Bool

    /// Called when new items are fetched from iCloud.
    /// The callback receives the new items; the caller is responsible for merging.
    var onItemsFetched: (([ClipboardItem]) -> Void)?

    init(enableCloudSync: Bool) {
        self.isEnabled = enableCloudSync
        if enableCloudSync {
            cloudSync.delegate = self
        }
    }

    // MARK: - Upload

    func scheduleUpload(items: [ClipboardItem]) {
        guard isEnabled, cloudSync.isSyncEnabled else { return }
        uploadDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cloudSync.uploadItems(items)
        }
        uploadDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func scheduleUpload(item: ClipboardItem) {
        guard isEnabled, cloudSync.isSyncEnabled else { return }
        pendingUploadItems[item.id] = item
        pendingDeleteIDs.remove(item.id)
        schedulePendingChangeFlush()
    }

    func scheduleDeletes(ids: Set<UUID>) {
        guard isEnabled, cloudSync.isSyncEnabled, !ids.isEmpty else { return }
        for id in ids {
            pendingUploadItems.removeValue(forKey: id)
            pendingDeleteIDs.insert(id)
        }
        schedulePendingChangeFlush()
    }

    private func schedulePendingChangeFlush() {
        uploadDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let uploadItems = Array(self.pendingUploadItems.values)
            let deleteIDs = self.pendingDeleteIDs
            self.pendingUploadItems.removeAll(keepingCapacity: true)
            self.pendingDeleteIDs.removeAll(keepingCapacity: true)
            if !uploadItems.isEmpty {
                self.cloudSync.uploadItems(uploadItems)
            }
            for id in deleteIDs {
                self.cloudSync.deleteRecord(id: id)
            }
        }
        uploadDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - CloudSyncDelegate

    nonisolated func cloudSync(_ service: CloudSyncService, didFetchItems fetchedItems: [ClipboardItem]) {
        Task { @MainActor in
            onItemsFetched?(fetchedItems)
        }
    }
}
