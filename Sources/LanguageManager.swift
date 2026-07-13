import Foundation
import SwiftUI
import os

struct AppLanguageOption: Identifiable, Hashable {
    let id: String
    let code: String
    let title: String
    let flag: String

    static let all: [AppLanguageOption] = [
        AppLanguageOption(id: "en", code: "en", title: "English", flag: "🇺🇸"),
        AppLanguageOption(id: "zh", code: "zh", title: "中文", flag: "🇨🇳"),
    ]

    static func option(for code: String) -> AppLanguageOption {
        all.first(where: { $0.code == LanguageManager.normalizedLanguage(code) }) ?? all[0]
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    static let supportedLanguages: Set<String> = ["en", "zh"]
    private let preferencesStore: AppPreferencesStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "Language")

    @Published private(set) var hasSelectedLanguage: Bool
    @Published private(set) var revision: UInt64 = 0
    @Published var language: String {
        didSet {
            let normalized = Self.normalizedLanguage(language)
            guard normalized == language else {
                language = normalized
                return
            }
            guard oldValue != language else { return }
            revision &+= 1
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

        let saved: String?
        do {
            saved = try self.preferencesStore.loadLanguage()
        } catch {
            logger.error("Failed to load language preference: \(error.localizedDescription)")
            saved = nil
        }

        if let saved {
            self.language = Self.normalizedLanguage(saved)
            self.hasSelectedLanguage = true
        } else {
            self.language = "en"
            self.hasSelectedLanguage = false
        }
    }

    var currentOption: AppLanguageOption {
        AppLanguageOption.option(for: language)
    }

    func selectLanguage(_ code: String) {
        let normalized = Self.normalizedLanguage(code)
        if language != normalized {
            language = normalized
        } else {
            do {
                _ = try preferencesStore.saveLanguage(normalized)
            } catch {
                logger.error("Failed to save language preference: \(error.localizedDescription)")
            }
        }
        if !hasSelectedLanguage {
            hasSelectedLanguage = true
            revision &+= 1
        }
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

    static func normalizedLanguage(_ raw: String) -> String {
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
