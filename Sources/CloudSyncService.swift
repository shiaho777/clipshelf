import Foundation
import CloudKit
import Security
import os

protocol CloudSyncDelegate: AnyObject {
    func cloudSync(_ service: CloudSyncService, didFetchItems items: [ClipboardItem])
}

final class CloudSyncService: ObservableObject {
    weak var delegate: CloudSyncDelegate?
    @Published var isSyncEnabled = false {
        didSet {
            guard oldValue != isSyncEnabled else { return }
            UserDefaults.standard.set(isSyncEnabled, forKey: "iCloudSyncEnabled")
            if isSyncEnabled { triggerSync() }
        }
    }
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: String?

    private var container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "ClipboardHistory", ownerName: CKCurrentUserDefaultName)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "CloudSync")
    private var serverChangeToken: CKServerChangeToken?
    private let changeTokenKey = "cloudSyncChangeToken"
    private let containerIdentifier: String?

    static let shared = CloudSyncService()

    init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
        _isSyncEnabled = Published(initialValue: UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"))
        loadChangeToken()
    }
    
    private func resolveContainer() -> CKContainer? {
        if let c = container { return c }
        let allowedIdentifiers = entitlementContainerIdentifiers()
        let id = containerIdentifier ?? allowedIdentifiers.first
        guard let id, allowedIdentifiers.contains(id) else {
            failSync("CloudKit container entitlement is missing")
            return nil
        }
        let c = CKContainer(identifier: id)
        container = c
        return c
    }

    private func entitlementContainerIdentifiers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else {
            return []
        }
        return value as? [String] ?? []
    }

    private func failSync(_ message: String) {
        logger.error("\(message)")
        if Thread.isMainThread {
            syncError = message
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.syncError = message
            }
        }
    }

    // MARK: - Upload

    /// Image store used to resolve image file URLs for CKAsset upload.
    var imageStore: ClipboardImageStore?

    func uploadItems(_ items: [ClipboardItem]) {
        guard isSyncEnabled else { return }
        // Sync all item types (text, richText, and image)
        guard !items.isEmpty else { return }

        // Ensure custom zone exists
        guard let db = resolveContainer()?.privateCloudDatabase else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        let modifyZonesOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone])
        modifyZonesOp.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.saveRecords(for: items)
            case .failure(let error):
                self?.logger.error("Failed to create zone: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.syncError = error.localizedDescription }
            }
        }
        db.add(modifyZonesOp)
    }

    private func saveRecords(for items: [ClipboardItem]) {
        let records = items.map { item -> CKRecord in
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: "ClipboardItem", recordID: recordID)
            record["content"] = item.content as CKRecordValue
            record["type"] = item.type.rawValue as CKRecordValue
            record["timestamp"] = item.timestamp as CKRecordValue
            record["isPinned"] = (item.isPinned ? 1 : 0) as CKRecordValue
            record["useCount"] = item.useCount as CKRecordValue
            if let rtfData = item.rtfData { record["rtfData"] = rtfData as CKRecordValue }
            if let ocrText = item.ocrText { record["ocrText"] = ocrText as CKRecordValue }
            // Attach image as CKAsset
            if item.type == .image, let fileName = item.imageFileName,
               let store = imageStore {
                let fileURL = store.fileURL(for: fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    record["imageAsset"] = CKAsset(fileURL: fileURL)
                    if let hash = item.imageHash { record["imageHash"] = hash as CKRecordValue }
                }
            }
            return record
        }

        guard let db = resolveContainer()?.privateCloudDatabase else { return }
        let operation = CKModifyRecordsOperation(recordsToSave: records)
        operation.savePolicy = .ifServerRecordUnchanged
        
        // Handle per-record conflicts with last-write-wins merge
        operation.perRecordSaveBlock = { [weak self] recordID, result in
            if case .failure(let error) = result {
                guard let ckError = error as? CKError,
                      ckError.code == .serverRecordChanged,
                      let serverRecord = ckError.serverRecord else {
                    self?.logger.error("Per-record save error: \(error.localizedDescription)")
                    return
                }
                // Last-write-wins: apply local values onto the server record
                if let localRecord = records.first(where: { $0.recordID == recordID }) {
                    for key in localRecord.allKeys() {
                        serverRecord[key] = localRecord[key]
                    }
                    let retryOp = CKModifyRecordsOperation(recordsToSave: [serverRecord])
                    retryOp.savePolicy = .changedKeys
                    db.add(retryOp)
                }
            }
        }
        
        operation.modifyRecordsResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.lastSyncDate = Date()
                    self?.syncError = nil
                case .failure(let error):
                    self?.logger.error("Upload failed: \(error.localizedDescription)")
                    self?.syncError = error.localizedDescription
                }
            }
        }
        db.add(operation)
    }

    // MARK: - Fetch Changes

    func fetchChanges(completion: @escaping ([ClipboardItem]) -> Void) {
        guard isSyncEnabled else { completion([]); return }

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = serverChangeToken

        guard let db = resolveContainer()?.privateCloudDatabase else {
            completion([])
            return
        }
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])

        var fetchedItems: [ClipboardItem] = []
        var deletedIDs: [UUID] = []

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            if let uuid = UUID(uuidString: recordID.recordName) {
                deletedIDs.append(uuid)
            }
        }

        operation.recordWasChangedBlock = { [weak self] _, result in
            switch result {
            case .success(let record):
                if let item = self?.clipboardItem(from: record) {
                    fetchedItems.append(item)
                }
            case .failure(let error):
                self?.logger.error("Record fetch error: \(error.localizedDescription)")
            }
        }

        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            if case .success(let outcome) = result {
                self?.serverChangeToken = outcome.serverChangeToken
                self?.saveChangeToken()
            } else if case .failure(let error) = result {
                self?.logger.error("Zone fetch error: \(error.localizedDescription)")
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.lastSyncDate = Date()
                    self?.syncError = nil
                    if !deletedIDs.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("ClipboardCloudDeleteItems"),
                            object: nil,
                            userInfo: ["ids": deletedIDs]
                        )
                    }
                    completion(fetchedItems)
                case .failure(let error):
                    self?.logger.error("Fetch changes failed: \(error.localizedDescription)")
                    self?.syncError = error.localizedDescription
                    completion([])
                }
            }
        }

        db.add(operation)
    }

    // MARK: - Full Sync

    func triggerSync() {
        guard isSyncEnabled else { return }
        fetchChanges { [weak self] fetchedItems in
            guard let self, !fetchedItems.isEmpty else { return }
            self.delegate?.cloudSync(self, didFetchItems: fetchedItems)
        }
    }

    // MARK: - Helpers

    private func clipboardItem(from record: CKRecord) -> ClipboardItem? {
        guard let content = record["content"] as? String,
              let typeRaw = record["type"] as? String,
              let type = ClipboardItem.ItemType(rawValue: typeRaw),
              let timestamp = record["timestamp"] as? Date else { return nil }

        let isPinned = (record["isPinned"] as? Int ?? 0) != 0
        let useCount = record["useCount"] as? Int ?? 0
        let rtfData = record["rtfData"] as? Data
        let ocrText = record["ocrText"] as? String

        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        // Handle image assets
        var imageFileName: String?
        var imageHash: String?
        if type == .image, let asset = record["imageAsset"] as? CKAsset,
           let assetURL = asset.fileURL,
           let store = imageStore {
            let fileName = "\(id.uuidString).png"
            if let data = try? Data(contentsOf: assetURL) {
                try? store.saveImageData(data, fileName: fileName)
                imageFileName = fileName
            }
            imageHash = record["imageHash"] as? String
        }

        return ClipboardItem(
            id: id,
            content: content,
            rtfData: rtfData,
            type: type,
            timestamp: timestamp,
            isPinned: isPinned,
            useCount: useCount,
            imageHash: imageHash,
            imageFileName: imageFileName,
            ocrText: ocrText
        )
    }

    // MARK: - Change Token Persistence

    private func loadChangeToken() {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return }
        serverChangeToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken() {
        guard let token = serverChangeToken else { return }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: changeTokenKey)
    }

    // MARK: - Delete Record

    /// Delete a single CloudKit record by its clipboard item UUID.
    func deleteRecord(id: UUID) {
        guard isSyncEnabled else { return }
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        guard let db = resolveContainer()?.privateCloudDatabase else { return }
        let operation = CKModifyRecordsOperation(recordIDsToDelete: [recordID])
        operation.modifyRecordsResultBlock = { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Delete record failed: \(error.localizedDescription)")
            }
        }
        db.add(operation)
    }

    // MARK: - Async/Await

    /// Async wrapper around the callback-based `fetchChanges(completion:)`.
    func fetchChanges() async -> [ClipboardItem] {
        await withCheckedContinuation { continuation in
            fetchChanges { items in
                continuation.resume(returning: items)
            }
        }
    }
}
