import Foundation
import SwiftUI
import os

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    static let supportedLanguages: Set<String> = ["en", "zh"]
    private let preferencesStore: AppPreferencesStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "Language")
    
    @Published var language: String {
        didSet {
            let normalized = Self.normalizedLanguage(language)
            guard normalized == language else {
                language = normalized
                return
            }
            guard oldValue != language else { return }
            do {
                _ = try preferencesStore.saveLanguage(language)
            } catch {
                logger.error("Failed to save language preference: \(error.localizedDescription)")
            }
        }
    }
    
    init(storageDirectory: URL? = nil, preferencesStore: AppPreferencesStore? = nil) {
        let resolvedStorageDirectory: URL
        if let storageDirectory {
            resolvedStorageDirectory = storageDirectory
        } else {
            resolvedStorageDirectory = AppStoragePaths.defaultStorageDirectory()
        }
        self.preferencesStore = preferencesStore ?? JSONAppPreferencesStore(storageDirectory: resolvedStorageDirectory)
        let initialLanguage: String
        do {
            initialLanguage = try self.preferencesStore.loadLanguage() ?? Self.defaultLanguage
        } catch {
            logger.error("Failed to load language preference: \(error.localizedDescription)")
            initialLanguage = Self.defaultLanguage
        }
        self.language = Self.normalizedLanguage(initialLanguage)
    }
    
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language == "zh" ? "zh-Hans" : "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    
    func l(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    func l(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }
    
    private static var defaultLanguage: String {
        normalizedLanguage(Locale.current.language.languageCode?.identifier ?? "en")
    }
    
    private static func normalizedLanguage(_ raw: String) -> String {
        let lowercased = raw.lowercased()
        if lowercased.hasPrefix("zh") {
            return "zh"
        }
        return supportedLanguages.contains(lowercased) ? lowercased : "en"
    }
}

extension String {
    var localized: String { LanguageManager.shared.l(self) }
    func localized(_ args: CVarArg...) -> String { String(format: localized, arguments: args) }
}
