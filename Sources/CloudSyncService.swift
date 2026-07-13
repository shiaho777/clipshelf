import Foundation
import CloudKit
import Security
import os

protocol CloudSyncDelegate: AnyObject {
    func cloudSync(_ service: CloudSyncService, didFetchItems items: [ClipboardItem])
}

enum CloudSyncReadiness: Equatable {
    case ready
    case checking
    case missingEntitlement
    case accountUnavailable(String)
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case unknown(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

final class CloudSyncService: ObservableObject {
    static let defaultContainerIdentifier = "iCloud.com.nicebro.ClipShelf"

    weak var delegate: CloudSyncDelegate?
    @Published var isSyncEnabled = false {
        didSet {
            guard oldValue != isSyncEnabled else { return }
            UserDefaults.standard.set(isSyncEnabled, forKey: "iCloudSyncEnabled")
            if isSyncEnabled {
                Task { @MainActor in
                    await self.prepareAndSync()
                }
            } else {
                syncError = nil
                readiness = .checking
            }
        }
    }
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var readiness: CloudSyncReadiness = .checking
    @Published private(set) var resolvedContainerIdentifier: String?

    private var container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "ClipboardHistory", ownerName: CKCurrentUserDefaultName)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "CloudSync")
    private var serverChangeToken: CKServerChangeToken?
    private let changeTokenKey = "cloudSyncChangeToken"
    private let preferredContainerIdentifier: String?
    private var zoneEnsureTask: Task<Bool, Never>?

    static let shared = CloudSyncService()

    init(containerIdentifier: String? = nil) {
        self.preferredContainerIdentifier = containerIdentifier
        _isSyncEnabled = Published(initialValue: UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"))
        loadChangeToken()
        if isSyncEnabled {
            Task { @MainActor in
                await self.refreshReadiness()
            }
        } else {
            readiness = .checking
        }
    }

    var statusSummary: String {
        switch readiness {
        case .ready:
            return ""
        case .checking:
            return "settings.icloud.status.checking".localized
        case .missingEntitlement:
            return "settings.icloud.error.missingEntitlement".localized
        case .accountUnavailable(let detail):
            return detail
        case .restricted:
            return "settings.icloud.error.restricted".localized
        case .couldNotDetermine:
            return "settings.icloud.error.couldNotDetermine".localized
        case .temporarilyUnavailable:
            return "settings.icloud.error.temporarilyUnavailable".localized
        case .unknown(let message):
            return message
        }
    }

    @MainActor
    func refreshReadiness() async {
        readiness = .checking
        syncError = nil

        let identifiers = availableContainerIdentifiers()
        guard let containerID = selectContainerIdentifier(from: identifiers) else {
            readiness = .missingEntitlement
            resolvedContainerIdentifier = nil
            container = nil
            failSync("settings.icloud.error.missingEntitlement".localized)
            return
        }

        resolvedContainerIdentifier = containerID
        let ckContainer = CKContainer(identifier: containerID)
        container = ckContainer

        do {
            let status = try await ckContainer.accountStatus()
            switch status {
            case .available:
                readiness = .ready
                syncError = nil
            case .noAccount:
                readiness = .accountUnavailable("settings.icloud.error.noAccount".localized)
                failSync("settings.icloud.error.noAccount".localized)
            case .restricted:
                readiness = .restricted
                failSync("settings.icloud.error.restricted".localized)
            case .couldNotDetermine:
                readiness = .couldNotDetermine
                failSync("settings.icloud.error.couldNotDetermine".localized)
            case .temporarilyUnavailable:
                readiness = .temporarilyUnavailable
                failSync("settings.icloud.error.temporarilyUnavailable".localized)
            @unknown default:
                readiness = .unknown("settings.icloud.error.unknown".localized)
                failSync("settings.icloud.error.unknown".localized)
            }
        } catch {
            readiness = .unknown(error.localizedDescription)
            failSync(error.localizedDescription)
        }
    }

    @MainActor
    private func prepareAndSync() async {
        await refreshReadiness()
        guard readiness.isReady else { return }
        _ = await ensureCustomZone()
        triggerSync()
    }

    private func selectContainerIdentifier(from identifiers: [String]) -> String? {
        if let preferred = preferredContainerIdentifier, identifiers.contains(preferred) {
            return preferred
        }
        if identifiers.contains(Self.defaultContainerIdentifier) {
            return Self.defaultContainerIdentifier
        }
        return identifiers.first
    }

    private func availableContainerIdentifiers() -> [String] {
        entitlementContainerIdentifiers()
    }

    private func resolveContainer() -> CKContainer? {
        if let c = container { return c }
        let identifiers = availableContainerIdentifiers()
        guard let id = selectContainerIdentifier(from: identifiers) else {
            failSync("settings.icloud.error.missingEntitlement".localized)
            Task { @MainActor in self.readiness = .missingEntitlement }
            return nil
        }
        resolvedContainerIdentifier = id
        let c = CKContainer(identifier: id)
        container = c
        return c
    }

    private func entitlementContainerIdentifiers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        var error: Unmanaged<CFError>?
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            &error
        ) else {
            return []
        }
        if let arr = value as? [String] { return arr }
        return []
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

    @MainActor
    private func ensureCustomZone() async -> Bool {
        if let existing = zoneEnsureTask {
            return await existing.value
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            guard let db = self.resolveContainer()?.privateCloudDatabase else { return false }
            let zone = CKRecordZone(zoneID: self.zoneID)
            do {
                _ = try await db.save(zone)
                return true
            } catch let error as CKError where error.code == .serverRejectedRequest || error.code == .zoneNotFound {
                // zone may already exist or needs creation via modify
            } catch {
                // continue with modify path
            }
            return await withCheckedContinuation { continuation in
                let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone])
                op.modifyRecordZonesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: true)
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                            continuation.resume(returning: true)
                            return
                        }
                        self.logger.error("Failed to create zone: \(error.localizedDescription)")
                        DispatchQueue.main.async { self.syncError = error.localizedDescription }
                        continuation.resume(returning: false)
                    }
                }
                db.add(op)
            }
        }
        zoneEnsureTask = task
        let ok = await task.value
        zoneEnsureTask = nil
        return ok
    }

    // MARK: - Upload

    /// Image store used to resolve image file URLs for CKAsset upload.
    var imageStore: ClipboardImageStore?

    func uploadItems(_ items: [ClipboardItem]) {
        guard isSyncEnabled else { return }
        guard !items.isEmpty else { return }

        Task { @MainActor in
            await self.refreshReadiness()
            guard self.readiness.isReady else { return }
            let zoneOK = await self.ensureCustomZone()
            guard zoneOK else { return }
            self.saveRecords(for: items)
        }
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
            failSync("settings.icloud.error.missingEntitlement".localized)
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
