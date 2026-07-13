import SwiftUI

struct SettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject var lang = LanguageManager.shared
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @ObservedObject var cloudSync = CloudSyncService.shared
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var selectedTab = 0
    @State private var showClearConfirm = false
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var importExportError: String?
    /// 0 = ZIP backup, 1 = CSV, 2 = Markdown
    @State private var exportFormat = 0
    
    private let historyLimits = [500, 1000, 10_000, 50_000, 100_000, 0]
    private let hotWindowLimits = [500, 1_000, 2_000, 5_000, 10_000]
    private let cleanupOptions: [(key: String, value: Int)] = [
        ("settings.cleanup.never", 0),
        ("settings.cleanup.1day", 1),
        ("settings.cleanup.3days", 3),
        ("settings.cleanup.7days", 7),
        ("settings.cleanup.30days", 30)
    ]
    
    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(lang.l("settings.tab.general"), systemImage: "gearshape") }
                .tag(0)
            rulesTab
                .tabItem { Label(lang.l("settings.tab.rules"), systemImage: "list.bullet.rectangle") }
                .tag(1)
            syncTab
                .tabItem { Label(lang.l("settings.tab.sync"), systemImage: "arrow.triangle.2.circlepath") }
                .tag(2)
            aboutTab
                .tabItem { Label(lang.l("settings.tab.about"), systemImage: "info.circle") }
                .tag(3)
        }
        .standardPopupLayout()
        .accessibilityIdentifier("settingsView")
        .onAppear {
            settingsVM.loadLaunchAtLoginPreferenceIfNeeded()
            // If AppDelegate requested a specific tab (e.g., Rules), navigate to it.
            let requestedTab = UserDefaults.standard.integer(forKey: "_settingsRequestedTab")
            if requestedTab > 0 {
                selectedTab = requestedTab
                UserDefaults.standard.removeObject(forKey: "_settingsRequestedTab")
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker(lang.l("settings.language"), selection: $lang.language) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
            }
            Section {
                Toggle(lang.l("settings.launchAtLogin"), isOn: $settingsVM.launchAtLogin)
                    .onChange(of: settingsVM.launchAtLogin) { _ in
                        settingsVM.handleLaunchAtLoginToggleChange()
                    }
                if let errorKey = settingsVM.launchAtLoginErrorKey {
                    Text(lang.l(errorKey)).foregroundColor(.red).font(.caption)
                }
            }
            Section {
                HotKeyRecorderView(hotKey: $hotKeyManager.mainHotKey)
                HotKeyRecorderView(hotKey: $hotKeyManager.queueHotKey, label: "hotkey.queue")
                HotKeyRecorderView(hotKey: $hotKeyManager.quickPasteHotKey, label: "hotkey.quickPaste")
            }
            Section {
                Picker(lang.l("settings.maxHistory"), selection: $clipboardManager.maxHistoryCount) {
                    ForEach(historyLimits, id: \.self) { limit in
                        Text(limit == 0 ? lang.l("settings.maxHistory.unlimited") : "\(limit)").tag(limit)
                    }
                }
                Picker(lang.l("settings.hotWindow"), selection: $clipboardManager.hotWindowCount) {
                    ForEach(hotWindowLimits, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                Text(lang.l("settings.hotWindow.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(lang.l("settings.autoCleanup"), selection: $clipboardManager.autoCleanupInterval) {
                    ForEach(cleanupOptions, id: \.value) { option in
                        Text(lang.l(option.key)).tag(option.value)
                    }
                }
            }
            Section {
                Toggle(lang.l("settings.smartPaste"), isOn: $clipboardManager.smartPasteEnabled)
                Text(lang.l("settings.smartPaste.description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                HStack {
                    Text(lang.l("snippets.title"))
                    Spacer()
                    Text("\(snippetManager.snippets.count)")
                        .foregroundColor(.secondary)
                }
                Toggle(lang.l("settings.snippetExpansion"), isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") },
                    set: { UserDefaults.standard.set($0, forKey: "snippetExpansionEnabled") }
                ))
                Text(lang.l("settings.snippetExpansion.description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                // Show a warning if expansion is enabled but Accessibility is not granted.
                if UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") && !AXIsProcessTrusted() {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(lang.l("snippet.accessibilityRequired"))
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button(lang.l("snippet.openPrivacy")) {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Rules Tab

    private var rulesTab: some View {
        Form {
            RulesSettingsView(clipboardManager: clipboardManager)
        }
        .formStyle(.grouped)
    }

    // MARK: - Sync Tab

    private var syncTab: some View {
        Form {
            Section {
                Toggle(lang.l("settings.icloudSync"), isOn: $cloudSync.isSyncEnabled)
                if let date = cloudSync.lastSyncDate {
                    HStack {
                        Text(lang.l("settings.lastSync"))
                        Spacer()
                        Text(date, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
                if let error = cloudSync.syncError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            Section {
                Picker(lang.l("settings.exportFormat"), selection: $exportFormat) {
                    Text(lang.l("settings.exportFormat.zip")).tag(0)
                    Text(lang.l("settings.exportFormat.csv")).tag(1)
                    Text(lang.l("settings.exportFormat.md")).tag(2)
                }
                .labelsHidden()
                Button(lang.l("settings.export")) { exportData() }
                if showExportSuccess {
                    Text(lang.l("settings.exportSuccess")).foregroundColor(.green).font(.caption)
                }
                if let error = importExportError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            Section {
                Button(lang.l("settings.import")) { importData() }
                Button(lang.l("settings.importMaccy")) { importFromMaccy() }
                Button(lang.l("settings.importAlfred")) { importFromAlfred() }
                if showImportSuccess {
                    Text(lang.l("settings.importSuccess")).foregroundColor(.green).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        Form {
            Section {
                HStack {
                    Text(lang.l("settings.version"))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(lang.l("about.platform"))
                    Spacer()
                    Text(lang.l("about.platformValue"))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(lang.l("about.itemsStored"))
                    Spacer()
                    Text("\(clipboardManager.items.count)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            Section(header: Text(lang.l("about.links"))) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/clipshelf")!)
                } label: {
                    HStack {
                        Image(systemName: "star")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text(lang.l("about.starGitHub"))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/clipshelf/blob/main/CHANGELOG.md")!)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                        Text(lang.l("about.changelog"))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/clipshelf/blob/main/CONTRIBUTING.md")!)
                } label: {
                    HStack {
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                        Text(lang.l("about.contributing"))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/clipshelf/issues/new?template=bug_report.md")!)
                } label: {
                    HStack {
                        Image(systemName: "ant")
                            .font(.system(size: 11))
                        Text(lang.l("about.reportBug"))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            Section {
                Button(lang.l("settings.clearAll")) {
                    showClearConfirm = true
                }
                .foregroundColor(.red)
                .alert(lang.l("settings.clearAllConfirm"), isPresented: $showClearConfirm) {
                    Button(lang.l("button.cancel"), role: .cancel) {}
                    Button(lang.l("button.clear"), role: .destructive) {
                        clipboardManager.clearAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let storageDirectory: URL = {
        return AppStoragePaths.defaultStorageDirectory()
    }()

    private func makeDataPortService() -> DataPortService {
        DataPortService(
            storageDirectory: Self.storageDirectory,
            historyStore: SQLiteHistoryStore(storageDirectory: Self.storageDirectory),
            imageStore: FileClipboardImageStore(storageDirectory: Self.storageDirectory)
        )
    }

    private func exportData() {
        let service = makeDataPortService()
        switch exportFormat {
        case 1:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "ClipboardHistory.csv"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try service.exportCSV(to: url, items: clipboardManager.items)
                showExportSuccess = true; importExportError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showExportSuccess = false }
            } catch { importExportError = error.localizedDescription }
        case 2:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "ClipboardHistory.md"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try service.exportMarkdown(to: url, items: clipboardManager.items)
                showExportSuccess = true; importExportError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showExportSuccess = false }
            } catch { importExportError = error.localizedDescription }
        default:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "clipbackup")!]
            panel.nameFieldStringValue = "ClipboardBackup.clipbackup"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try service.exportBackup(to: url, items: clipboardManager.items)
                showExportSuccess = true; importExportError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showExportSuccess = false }
            } catch { importExportError = error.localizedDescription }
        }
    }

    private func importFromMaccy() {
        let panel = NSOpenPanel()
        panel.title = "Select Maccy Database"
        panel.message = "Typical location: ~/Library/Containers/org.p0deje.Maccy/"
        panel.allowedContentTypes = [.init(filenameExtension: "sqlite") ?? .data]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let merged = try makeDataPortService().importMaccy(from: url, existingItems: clipboardManager.items, mode: .merge)
            clipboardManager.items = merged
            showImportSuccess = true; importExportError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showImportSuccess = false }
        } catch { importExportError = error.localizedDescription }
    }

    private func importFromAlfred() {
        let panel = NSOpenPanel()
        panel.title = "Select Alfred Clipboard Database"
        panel.message = "Typical location: ~/Library/Application Support/Alfred/Databases/"
        panel.allowedContentTypes = [.init(filenameExtension: "alfdb") ?? .data]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let merged = try makeDataPortService().importAlfred(from: url, existingItems: clipboardManager.items, mode: .merge)
            clipboardManager.items = merged
            showImportSuccess = true; importExportError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showImportSuccess = false }
        } catch { importExportError = error.localizedDescription }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "clipbackup")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let merged = try makeDataPortService().importBackup(from: url, existingItems: clipboardManager.items, mode: .merge)
            clipboardManager.items = merged
            showImportSuccess = true
            importExportError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showImportSuccess = false }
        } catch {
            importExportError = error.localizedDescription
        }
    }
}
