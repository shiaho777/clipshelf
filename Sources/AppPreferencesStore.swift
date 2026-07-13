import Foundation

protocol AppPreferencesStore {
    func loadLanguage() throws -> String?
    @discardableResult func saveLanguage(_ language: String) throws -> Bool
    func loadLaunchAtLogin() throws -> Bool?
    @discardableResult func saveLaunchAtLogin(_ enabled: Bool) throws -> Bool
    func loadMaxHistoryCount() throws -> Int?
    @discardableResult func saveMaxHistoryCount(_ value: Int) throws -> Bool
    func loadAutoCleanupInterval() throws -> Int?
    @discardableResult func saveAutoCleanupInterval(_ value: Int) throws -> Bool
    func loadExcludedBundleIDs() throws -> Set<String>?
    @discardableResult func saveExcludedBundleIDs(_ bundleIDs: Set<String>) throws -> Bool
    func loadSmartPasteEnabled() throws -> Bool?
    @discardableResult func saveSmartPasteEnabled(_ enabled: Bool) throws -> Bool
    func loadHotWindowCount() throws -> Int?
    @discardableResult func saveHotWindowCount(_ value: Int) throws -> Bool
}

final class JSONAppPreferencesStore: AppPreferencesStore {
    private struct LanguagePayload: Codable { let language: String }
    private struct BoolPayload: Codable { let value: Bool }
    private struct IntPayload: Codable { let value: Int }
    private struct ExcludedAppsPayload: Codable { let bundleIDs: [String] }
    
    private let languageURL: URL
    private let launchAtLoginURL: URL
    private let maxHistoryCountURL: URL
    private let autoCleanupIntervalURL: URL
    private let excludedAppsURL: URL
    private let smartPasteURL: URL
    private let hotWindowCountURL: URL
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(storageDirectory: URL, userDefaults: UserDefaults = .standard) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        languageURL = storageDirectory.appendingPathComponent("app_language.json")
        launchAtLoginURL = storageDirectory.appendingPathComponent("launch_at_login.json")
        maxHistoryCountURL = storageDirectory.appendingPathComponent("max_history_count.json")
        autoCleanupIntervalURL = storageDirectory.appendingPathComponent("auto_cleanup_interval.json")
        excludedAppsURL = storageDirectory.appendingPathComponent("excluded_apps.json")
        smartPasteURL = storageDirectory.appendingPathComponent("smart_paste.json")
        hotWindowCountURL = storageDirectory.appendingPathComponent("hot_window_count.json")
        self.userDefaults = userDefaults
    }
    
    // MARK: - Language
    
    func loadLanguage() throws -> String? {
        if FileManager.default.fileExists(atPath: languageURL.path) {
            let data = try Data(contentsOf: languageURL)
            return try decoder.decode(LanguagePayload.self, from: data).language
        }
        return userDefaults.string(forKey: "appLanguage")
    }
    
    @discardableResult
    func saveLanguage(_ language: String) throws -> Bool {
        let encoded = try encoder.encode(LanguagePayload(language: language))
        try encoded.write(to: languageURL, options: .atomic)
        return true
    }
    
    // MARK: - Launch at Login
    
    func loadLaunchAtLogin() throws -> Bool? {
        if FileManager.default.fileExists(atPath: launchAtLoginURL.path) {
            let data = try Data(contentsOf: launchAtLoginURL)
            return try decoder.decode(BoolPayload.self, from: data).value
        }
        return userDefaults.object(forKey: "launchAtLogin") as? Bool
    }
    
    @discardableResult
    func saveLaunchAtLogin(_ enabled: Bool) throws -> Bool {
        let encoded = try encoder.encode(BoolPayload(value: enabled))
        try encoded.write(to: launchAtLoginURL, options: .atomic)
        return true
    }
    
    // MARK: - Max History Count
    
    func loadMaxHistoryCount() throws -> Int? {
        if FileManager.default.fileExists(atPath: maxHistoryCountURL.path) {
            let data = try Data(contentsOf: maxHistoryCountURL)
            return try decoder.decode(IntPayload.self, from: data).value
        }
        return userDefaults.object(forKey: "maxHistoryCount") as? Int
    }
    
    @discardableResult
    func saveMaxHistoryCount(_ value: Int) throws -> Bool {
        let encoded = try encoder.encode(IntPayload(value: value))
        try encoded.write(to: maxHistoryCountURL, options: .atomic)
        return true
    }
    
    // MARK: - Auto Cleanup Interval
    
    func loadAutoCleanupInterval() throws -> Int? {
        if FileManager.default.fileExists(atPath: autoCleanupIntervalURL.path) {
            let data = try Data(contentsOf: autoCleanupIntervalURL)
            return try decoder.decode(IntPayload.self, from: data).value
        }
        return userDefaults.object(forKey: "autoCleanupInterval") as? Int
    }
    
    @discardableResult
    func saveAutoCleanupInterval(_ value: Int) throws -> Bool {
        let encoded = try encoder.encode(IntPayload(value: value))
        try encoded.write(to: autoCleanupIntervalURL, options: .atomic)
        return true
    }
    
    // MARK: - Excluded Bundle IDs
    
    func loadExcludedBundleIDs() throws -> Set<String>? {
        if FileManager.default.fileExists(atPath: excludedAppsURL.path) {
            let data = try Data(contentsOf: excludedAppsURL)
            let payload = try decoder.decode(ExcludedAppsPayload.self, from: data)
            return Set(payload.bundleIDs)
        }
        if let legacyData = userDefaults.data(forKey: "excludedApps"),
           let legacyBundleIDs = try? JSONDecoder().decode(Set<String>.self, from: legacyData) {
            return legacyBundleIDs
        }
        return nil
    }
    
    @discardableResult
    func saveExcludedBundleIDs(_ bundleIDs: Set<String>) throws -> Bool {
        let payload = ExcludedAppsPayload(bundleIDs: bundleIDs.sorted())
        let encoded = try encoder.encode(payload)
        try encoded.write(to: excludedAppsURL, options: .atomic)
        return true
    }
    
    // MARK: - Smart Paste
    
    func loadSmartPasteEnabled() throws -> Bool? {
        if FileManager.default.fileExists(atPath: smartPasteURL.path) {
            let data = try Data(contentsOf: smartPasteURL)
            return try decoder.decode(BoolPayload.self, from: data).value
        }
        return nil
    }
    
    @discardableResult
    func saveSmartPasteEnabled(_ enabled: Bool) throws -> Bool {
        let encoded = try encoder.encode(BoolPayload(value: enabled))
        try encoded.write(to: smartPasteURL, options: .atomic)
        return true
    }

    // MARK: - Hot Window Count

    func loadHotWindowCount() throws -> Int? {
        if FileManager.default.fileExists(atPath: hotWindowCountURL.path) {
            let data = try Data(contentsOf: hotWindowCountURL)
            return try decoder.decode(IntPayload.self, from: data).value
        }
        return userDefaults.object(forKey: "hotWindowCount") as? Int
    }

    @discardableResult
    func saveHotWindowCount(_ value: Int) throws -> Bool {
        let encoded = try encoder.encode(IntPayload(value: value))
        try encoded.write(to: hotWindowCountURL, options: .atomic)
        return true
    }
}
