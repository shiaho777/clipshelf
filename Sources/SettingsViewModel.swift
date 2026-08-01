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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "Settings")
    
    init(
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginServiceFactory.defaultService(),
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
                resolvedStorageDirectory = AppStoragePaths.defaultStorageDirectory()
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
        didLoadLaunchAtLoginPreference = true
        // The system is the source of truth: the toggle mirrors the actual
        // registration state, not just the stored preference. A stored "on"
        // with no registration means the login item was lost (reinstall,
        // signature change, system cleanup) — the app re-registers at launch.
        suppressLaunchAtLoginChange = true
        launchAtLogin = launchAtLoginService.isEnabled
        // Reset immediately: if the value didn't change, onChange never fires
        // and must not swallow the user's next toggle.
        suppressLaunchAtLoginChange = false
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
