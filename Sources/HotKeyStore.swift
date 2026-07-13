import Foundation

protocol HotKeyStore {
    func loadMainHotKey() throws -> HotKeyConfig?
    @discardableResult
    func saveMainHotKey(_ config: HotKeyConfig) throws -> Bool
    func loadQueueHotKey() throws -> HotKeyConfig?
    @discardableResult
    func saveQueueHotKey(_ config: HotKeyConfig) throws -> Bool
    func loadQuickPasteHotKey() throws -> HotKeyConfig?
    @discardableResult
    func saveQuickPasteHotKey(_ config: HotKeyConfig) throws -> Bool
}

final class JSONHotKeyStore: HotKeyStore {
    private struct HotKeyPayload: Codable {
        var main: HotKeyConfig
        var queue: HotKeyConfig?
        var quickPaste: HotKeyConfig?
    }
    
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastConfig: HotKeyConfig?
    private var lastConfigData: Data?
    private var lastQueueConfig: HotKeyConfig?
    private var lastQueueConfigData: Data?
    private var lastQuickPasteConfig: HotKeyConfig?
    
    init(storageDirectory: URL) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        fileURL = storageDirectory.appendingPathComponent("hotkeys.json")
    }
    
    func loadMainHotKey() throws -> HotKeyConfig? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        // Try new payload format first, fall back to legacy single-config
        if let payload = try? decoder.decode(HotKeyPayload.self, from: data) {
            lastConfig = payload.main
            lastQueueConfig = payload.queue
            lastQuickPasteConfig = payload.quickPaste
            return payload.main
        }
        let config = try decoder.decode(HotKeyConfig.self, from: data)
        lastConfig = config
        lastConfigData = data
        return config
    }
    
    @discardableResult
    func saveMainHotKey(_ config: HotKeyConfig) throws -> Bool {
        lastConfig = config
        return try savePayload()
    }
    
    func loadQueueHotKey() throws -> HotKeyConfig? {
        // Already loaded in loadMainHotKey
        return lastQueueConfig
    }
    
    @discardableResult
    func saveQueueHotKey(_ config: HotKeyConfig) throws -> Bool {
        lastQueueConfig = config
        return try savePayload()
    }
    
    func loadQuickPasteHotKey() throws -> HotKeyConfig? {
        return lastQuickPasteConfig
    }
    
    @discardableResult
    func saveQuickPasteHotKey(_ config: HotKeyConfig) throws -> Bool {
        lastQuickPasteConfig = config
        return try savePayload()
    }
    
    private func savePayload() throws -> Bool {
        let payload = HotKeyPayload(
            main: lastConfig ?? .defaultMain,
            queue: lastQueueConfig,
            quickPaste: lastQuickPasteConfig
        )
        let encoded = try encoder.encode(payload)
        try encoded.write(to: fileURL, options: .atomic)
        return true
    }
}
