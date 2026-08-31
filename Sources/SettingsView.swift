import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject var lang = LanguageManager.shared
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var selectedTab = 0
    @State private var showClearConfirm = false
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var importExportError: String?
    /// 0 = ZIP backup, 1 = CSV, 2 = Markdown
    @State private var exportFormat = 0
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    /// Embedded mode (inside the main panel) hides the window-only header
    /// handling and starts on the caller-chosen section.
    var initialTab: Int = 0
    var showsOwnHeader: Bool = true

    private let historyLimits = [500, 1000, 10_000, 50_000, 100_000, 0]
    private let hotWindowLimits = [500, 1_000, 2_000, 5_000, 10_000]
    private let cleanupOptions: [(key: String, value: Int)] = [
        ("settings.cleanup.never", 0),
        ("settings.cleanup.1day", 1),
        ("settings.cleanup.3days", 3),
        ("settings.cleanup.7days", 7),
        ("settings.cleanup.30days", 30)
    ]

    // MARK: In-panel section builders (used by SettingsEmbeddedView)

    var generalSectionInPanel: some View {
        SettingsSectionStack(isInPanel: true) {
            SettingsCard(title: nil) {
                SettingsRow(label: lang.l("settings.language")) {
                    Picker("", selection: Binding(
                        get: { lang.language },
                        set: { lang.selectLanguage($0) }
                    )) {
                        ForEach(AppLanguageOption.all) { option in
                            Text("\(option.flag)  \(option.title)").tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsRow(label: lang.l("settings.launchAtLogin")) {
                    Toggle("", isOn: $settingsVM.launchAtLogin)
                        .labelsHidden()
                        .onChange(of: settingsVM.launchAtLogin) { _ in
                            settingsVM.handleLaunchAtLoginToggleChange()
                        }
                }
                if let errorKey = settingsVM.launchAtLoginErrorKey {
                    Text(lang.l(errorKey))
                        .font(.system(size: DesignSystem.FontSize.caption))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                }
            }
            SettingsCard(title: lang.l("settings.hotkeys.section")) {
                HotKeyRecorderView(hotKey: $hotKeyManager.mainHotKey)
                HotKeyRecorderView(hotKey: $hotKeyManager.queueHotKey, label: "hotkey.queue")
                HotKeyRecorderView(hotKey: $hotKeyManager.quickPasteHotKey, label: "hotkey.quickPaste")
            }
            SettingsCard(title: lang.l("settings.history.section")) {
                SettingsRow(label: lang.l("settings.maxHistory")) {
                    Picker("", selection: $clipboardManager.maxHistoryCount) {
                        ForEach(historyLimits, id: \.self) { limit in
                            Text(limit == 0 ? lang.l("settings.maxHistory.unlimited") : "\(limit)").tag(limit)
                        }
                    }
                    .labelsHidden()
                }
                SettingsRow(label: lang.l("settings.hotWindow")) {
                    Picker("", selection: $clipboardManager.hotWindowCount) {
                        ForEach(hotWindowLimits, id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }
                    .labelsHidden()
                }
                Text(lang.l("settings.hotWindow.description"))
                    .font(.system(size: DesignSystem.FontSize.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                SettingsRow(label: lang.l("settings.autoCleanup")) {
                    Picker("", selection: $clipboardManager.autoCleanupInterval) {
                        ForEach(cleanupOptions, id: \.value) { option in
                            Text(lang.l(option.key)).tag(option.value)
                        }
                    }
                    .labelsHidden()
                }
                SettingsRow(label: lang.l("settings.smartPaste")) {
                    Toggle("", isOn: $clipboardManager.smartPasteEnabled)
                        .labelsHidden()
                }
                Text(lang.l("settings.smartPaste.description"))
                    .font(.system(size: DesignSystem.FontSize.caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
            }
            SettingsCard(title: lang.l("snippets.title")) {
                SettingsRow(label: lang.l("settings.snippetExpansion")) {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") },
                        set: { UserDefaults.standard.set($0, forKey: "snippetExpansionEnabled") }
                    ))
                    .labelsHidden()
                }
                Text(lang.l("settings.snippetExpansion.description"))
                    .font(.system(size: DesignSystem.FontSize.caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                // Show a warning if expansion is enabled but Accessibility is not granted.
                if UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") && !accessibilityTrusted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: DesignSystem.FontSize.caption))
                        Text(lang.l("snippet.accessibilityRequired"))
                            .font(.system(size: DesignSystem.FontSize.caption))
                            .foregroundColor(.orange)
                        Spacer()
                        Button(lang.l("snippet.openPrivacy")) {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                        .font(.system(size: DesignSystem.FontSize.caption))
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
    }

    var rulesSectionInPanel: some View {
        SettingsSectionStack(isInPanel: true) {
            RulesSettingsView(clipboardManager: clipboardManager)
        }
    }

    var dataSectionInPanel: some View {
        SettingsSectionStack(isInPanel: true) {
            SettingsCard(title: lang.l("settings.export")) {
                SettingsRow(label: lang.l("settings.exportFormat")) {
                    Picker("", selection: $exportFormat) {
                        Text(lang.l("settings.exportFormat.zip")).tag(0)
                        Text(lang.l("settings.exportFormat.csv")).tag(1)
                        Text(lang.l("settings.exportFormat.md")).tag(2)
                    }
                    .labelsHidden()
                }
                Button {
                    exportData()
                } label: {
                    Text(lang.l("settings.export"))
                        .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                if showExportSuccess {
                    captionText(lang.l("settings.exportSuccess"), color: .green)
                }
                if let error = importExportError {
                    captionText(error, color: .red)
                }
            }
            SettingsCard(title: lang.l("settings.import")) {
                dataButton(lang.l("settings.import")) { importData() }
                dataButton(lang.l("settings.importMaccy")) { importFromMaccy() }
                dataButton(lang.l("settings.importAlfred")) { importFromAlfred() }
                if showImportSuccess {
                    captionText(lang.l("settings.importSuccess"), color: .green)
                }
            }
        }
    }

    private func dataButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func captionText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DesignSystem.FontSize.caption))
            .foregroundColor(color)
            .padding(.horizontal, 4)
    }

    var aboutSectionInPanel: some View {
        SettingsSectionStack(isInPanel: true) {
            SettingsCard(title: nil) {
                SettingsRow(label: lang.l("settings.version")) {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                SettingsRow(label: lang.l("about.platform")) {
                    Text(lang.l("about.platformValue"))
                        .foregroundColor(.secondary)
                }
                SettingsRow(label: lang.l("about.itemsStored")) {
                    Text("\(clipboardManager.totalStoredCount)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            SettingsCard(title: lang.l("about.links")) {
                aboutLink(icon: "star", key: "about.starGitHub", url: "https://github.com/shiaho777/clipshelf")
                aboutLink(icon: "clock.arrow.circlepath", key: "about.changelog", url: "https://github.com/shiaho777/clipshelf/blob/main/CHANGELOG.md")
                aboutLink(icon: "person.2", key: "about.contributing", url: "https://github.com/shiaho777/clipshelf/blob/main/CONTRIBUTING.md")
                aboutLink(icon: "ant", key: "about.reportBug", url: "https://github.com/shiaho777/clipshelf/issues/new?template=bug_report.md")
            }
            SettingsCard(title: nil) {
                Button {
                    showClearConfirm = true
                } label: {
                    Text(lang.l("settings.clearAll"))
                        .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .alert(lang.l("settings.clearAllConfirm"), isPresented: $showClearConfirm) {
                    Button(lang.l("button.cancel"), role: .cancel) {}
                    Button(lang.l("button.clear"), role: .destructive) {
                        clipboardManager.clearAll()
                    }
                }
            }
        }
    }

    private func aboutLink(icon: String, key: String, url: String) -> some View {
        Button {
            NSWorkspace.shared.open(URL(string: url)!)
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(lang.l(key))
                    .font(.system(size: DesignSystem.FontSize.secondary))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsOwnHeader {
                Picker("", selection: $selectedTab) {
                    Text(lang.l("settings.tab.general")).tag(0)
                    Text(lang.l("settings.tab.rules")).tag(1)
                    Text(lang.l("settings.tab.data")).tag(2)
                    Text(lang.l("settings.tab.about")).tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                // The settings window uses full-size content view, so content starts
                // under the titlebar (28pt). 40pt clears it; at 12pt the segmented
                // control's top 2pt was clipped by the traffic-light row.
                .padding(.top, 40)
                .padding(.bottom, 8)
            }

            Group {
                switch selectedTab {
                case 0:
                    generalTab
                case 1:
                    rulesTab
                case 2:
                    dataTab
                default:
                    aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Grouped forms paint their own opaque background by default; hide it
        // so the window's HUD vibrancy shows through like on the main panel.
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("settingsView")
        .onAppear {
            accessibilityTrusted = AXIsProcessTrusted()
            settingsVM.loadLaunchAtLoginPreferenceIfNeeded()
            let requestedTab = UserDefaults.standard.integer(forKey: "_settingsRequestedTab")
            if requestedTab > 0 {
                selectedTab = requestedTab
                UserDefaults.standard.removeObject(forKey: "_settingsRequestedTab")
            } else if !showsOwnHeader {
                selectedTab = initialTab
            }
        }
    }
    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker(lang.l("settings.language"), selection: Binding(
                    get: { lang.language },
                    set: { lang.selectLanguage($0) }
                )) {
                    ForEach(AppLanguageOption.all) { option in
                        Text("\(option.flag)  \(option.title)").tag(option.code)
                    }
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
                if UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") && !accessibilityTrusted {
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
        .id("settings-general-tab")
    }
    // MARK: - Rules Tab

    private var rulesTab: some View {
        Form {
            RulesSettingsView(clipboardManager: clipboardManager)
        }
        .formStyle(.grouped)
    }

    // MARK: - Sync Tab

    private var dataTab: some View {
        Form {
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
        .id("settings-data-tab")
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
                    Text("\(clipboardManager.totalStoredCount)")
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
        .id("settings-about-tab")
    }

    // MARK: - Embedded Sections (in-panel settings)

    /// Settings sections reused by `SettingsEmbeddedView`, which renders them
    /// inside the main panel instead of a separate window.
    var embeddedSections: [some View] {
        [AnyView(generalTab), AnyView(rulesTab), AnyView(dataTab), AnyView(aboutTab)]
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
        panel.title = lang.l("settings.importMaccy.panelTitle")
        panel.message = lang.l("settings.importMaccy.panelMessage")
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
        panel.title = lang.l("settings.importAlfred.panelTitle")
        panel.message = lang.l("settings.importAlfred.panelMessage")
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
