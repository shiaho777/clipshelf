import Foundation
import os

final class ClipboardPreferencesManager {
    private let preferencesStore: AppPreferencesStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "Preferences")

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
    }

    func loadExcludedBundleIDs() -> Set<String>? {
        do { return try preferencesStore.loadExcludedBundleIDs() }
        catch { logger.error("Failed to load excluded apps: \(error.localizedDescription)"); return nil }
    }

    func saveExcludedBundleIDs(_ ids: Set<String>) {
        do { _ = try preferencesStore.saveExcludedBundleIDs(ids) }
        catch { logger.error("Failed to save excluded apps: \(error.localizedDescription)") }
    }

    func loadMaxHistoryCount() -> Int? {
        do { return try preferencesStore.loadMaxHistoryCount() }
        catch { logger.error("Failed to load max history count: \(error.localizedDescription)"); return nil }
    }

    func saveMaxHistoryCount(_ value: Int) {
        do { _ = try preferencesStore.saveMaxHistoryCount(value) }
        catch { logger.error("Failed to save max history count: \(error.localizedDescription)") }
    }

    func loadAutoCleanupInterval() -> Int? {
        do { return try preferencesStore.loadAutoCleanupInterval() }
        catch { logger.error("Failed to load auto cleanup interval: \(error.localizedDescription)"); return nil }
    }

    func saveAutoCleanupInterval(_ value: Int) {
        do { _ = try preferencesStore.saveAutoCleanupInterval(value) }
        catch { logger.error("Failed to save auto cleanup interval: \(error.localizedDescription)") }
    }

    func loadSmartPasteEnabled() -> Bool? {
        do { return try preferencesStore.loadSmartPasteEnabled() }
        catch { logger.error("Failed to load smart paste pref: \(error.localizedDescription)"); return nil }
    }

    func saveSmartPasteEnabled(_ enabled: Bool) {
        do { _ = try preferencesStore.saveSmartPasteEnabled(enabled) }
        catch { logger.error("Failed to save smart paste pref: \(error.localizedDescription)") }
    }

    func loadHotWindowCount() -> Int? {
        do { return try preferencesStore.loadHotWindowCount() }
        catch { logger.error("Failed to load hot window count: \(error.localizedDescription)"); return nil }
    }

    func saveHotWindowCount(_ value: Int) {
        do { _ = try preferencesStore.saveHotWindowCount(value) }
        catch { logger.error("Failed to save hot window count: \(error.localizedDescription)") }
    }
}
