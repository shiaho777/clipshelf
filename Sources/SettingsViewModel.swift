import Foundation
import Combine
import os

final class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin = false
    @Published var launchAtLoginErrorKey: String?
    
    private var suppressLaunchAtLoginChange = false
    private var didLoadLaunchAtLoginPreference = false
    private let launchAtLoginService: LaunchAtLoginService
    private let preferencesStore: AppPreferencesStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "Settings")
    
    init(
        launchAtLoginService: LaunchAtLoginService = SMAppLaunchAtLoginService(),
        preferencesStore: AppPreferencesStore? = nil,
        storageDirectory: URL? = nil
    ) {
        self.launchAtLoginService = launchAtLoginService
        
        if let preferencesStore {
            self.preferencesStore = preferencesStore
        } else {
            let resolvedStorageDirectory: URL
            if let storageDirectory {
                resolvedStorageDirectory = storageDirectory
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                resolvedStorageDirectory = appSupport.appendingPathComponent("ClipboardManager")
            }
            self.preferencesStore = JSONAppPreferencesStore(storageDirectory: resolvedStorageDirectory)
        }
    }
    
    func handleLaunchAtLoginToggleChange() {
        guard !suppressLaunchAtLoginChange else {
            suppressLaunchAtLoginChange = false
            return
        }
        setLaunchAtLogin(launchAtLogin)
    }
    
    func loadLaunchAtLoginPreferenceIfNeeded() {
        guard !didLoadLaunchAtLoginPreference else { return }
        do {
            launchAtLogin = try preferencesStore.loadLaunchAtLogin() ?? false
            didLoadLaunchAtLoginPreference = true
        } catch {
            didLoadLaunchAtLoginPreference = true
            launchAtLogin = false
            logger.error("Failed to load launch-at-login preference: \(error.localizedDescription)")
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
        } catch {
            suppressLaunchAtLoginChange = true
            launchAtLogin = !enabled
            launchAtLoginErrorKey = "settings.launchAtLoginFailed"
            logger.error("Failed to update launch-at-login: \(error.localizedDescription)")
            return
        }
        
        persistLaunchAtLoginPreference(enabled)
        launchAtLoginErrorKey = nil
    }
    
    private func persistLaunchAtLoginPreference(_ enabled: Bool) {
        do {
            _ = try preferencesStore.saveLaunchAtLogin(enabled)
        } catch {
            logger.error("Failed to save launch-at-login preference: \(error.localizedDescription)")
        }
    }
}
