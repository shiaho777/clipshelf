import SwiftUI

/// Settings rendered inside the main panel (no separate window).
///
/// Reuses the main panel's visual language so the two pages read as one app:
/// a `SheetHeader`-style header row, a capsule section switcher built from the
/// same ingredients as the history filter chips (`filterButton`), and the
/// shared section content. The standalone-window `SettingsView` remains for
/// any future host that wants a modal settings window.
struct SettingsEmbeddedView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    var onBack: () -> Void

    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sectionAnimation
    // @AppStorage, not @State: the settings page remounts on every re-entry
    // (page = .history tears the view down), so @State reset the tab to
    // General each time. Also keeps the choice across relaunches.
    @AppStorage("settings.section") private var section = 0

    private let sectionKeys = ["settings.tab.general", "settings.tab.rules", "settings.tab.data", "settings.tab.about"]

    var body: some View {
        VStack(spacing: 0) {
            // Header row — matches the panel's search-row geometry.
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(lang.l("button.back"))
                            .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.05))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.l("button.back"))

                Spacer()

                sectionSwitcher
            }
            .padding(.horizontal, 14)
            // fullSizeContentView: keep clear of the transparent titlebar.
            .padding(.top, 36)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            settingsContent
        }
        .transition(.opacity)
        // Honor a requested tab (e.g. the gear context-menu "Test Rules"
        // action writes _settingsRequestedTab). Previously only the unused
        // window variant read this key, so the request silently landed on
        // the General section.
        .onAppear {
            let requested = UserDefaults.standard.integer(forKey: "_settingsRequestedTab")
            if requested > 0, requested < sectionKeys.count {
                section = requested
            }
            UserDefaults.standard.removeObject(forKey: "_settingsRequestedTab")
        }
        .onChange(of: section) { newValue in
            // Persist the tab only for organic navigation; a _settingsRequestedTab
            // jump (gear → "Test Rules") is one-shot and must not overwrite it.
            if UserDefaults.standard.object(forKey: "_settingsRequestedTab") == nil {
                UserDefaults.standard.set(newValue, forKey: "settings.section")
            }
        }
    }

    /// Capsule section switcher — same visual recipe as the history filter chips:
    /// 12pt text, active segment gets a control-background capsule with soft shadow.
    private var sectionSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(0..<sectionKeys.count, id: \.self) { i in
                Text(lang.l(sectionKeys[i]))
                    .font(.system(size: 12, weight: section == i ? .semibold : .regular))
                    .foregroundColor(section == i ? .primary : .secondary.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if section == i {
                            Capsule()
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                                .shadow(color: .black.opacity(0.03), radius: 0.5)
                                .matchedGeometryEffect(id: "activeSettingsSection", in: sectionAnimation)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78)) {
                            section = i
                        }
                    }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            switch section {
            case 0:
                SettingsGeneralSectionPanel(clipboardManager: clipboardManager, snippetManager: snippetManager)
            case 1:
                SettingsRulesSectionPanel(clipboardManager: clipboardManager)
            case 2:
                SettingsDataSectionPanel(clipboardManager: clipboardManager)
            default:
                SettingsAboutSectionPanel(clipboardManager: clipboardManager)
            }
        }
    }
}
import SwiftUI
import AppKit

// MARK: - In-Panel Settings Sections
//
// Each section is a standalone View that owns its own @State so toggles,
// pickers and buttons stay live while embedded in the main panel
// (SettingsEmbeddedView). These deliberately do NOT live as computed
// properties on `SettingsView`: a computed property there produced fresh view
// instances on every render, resetting @State and breaking interaction.


struct SettingsGeneralSectionPanel: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var hotKeyManager = HotKeyManager.shared
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var accessibilityTrusted = AXIsProcessTrusted()

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
        SettingsSectionStack(isInPanel: true) {
            SettingsCard(title: nil) {
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
            }
            .onAppear {
                // Mirror the system registration state before first interaction.
                // Without this the toggle showed OFF while login-launch was
                // actually enabled, and the first tap silently disabled it.
                settingsVM.loadLaunchAtLoginPreferenceIfNeeded()
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
}

struct SettingsRulesSectionPanel: View {
    @ObservedObject var clipboardManager: ClipboardManager

    var body: some View {
        SettingsSectionStack(isInPanel: true) {
            RulesSettingsView(clipboardManager: clipboardManager)
        }
    }
}

struct SettingsDataSectionPanel: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var importExportError: String?
    /// 0 = ZIP backup, 1 = CSV, 2 = Markdown. Persisted: the view remounts on
    /// every re-entry, so @State reset the picker to ZIP each time.
    @AppStorage("settings.exportFormat") private var exportFormat = 0

    private static let storageDirectory: URL = AppStoragePaths.defaultStorageDirectory()

    private func makeDataPortService() -> DataPortService {
        DataPortService(
            storageDirectory: Self.storageDirectory,
            historyStore: SQLiteHistoryStore(storageDirectory: Self.storageDirectory),
            imageStore: FileClipboardImageStore(storageDirectory: Self.storageDirectory)
        )
    }

    var body: some View {
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
                filledButton(lang.l("settings.export")) { exportData() }
                if showExportSuccess {
                    captionText(lang.l("settings.exportSuccess"), color: .green)
                }
                if let error = importExportError {
                    captionText(error, color: .red)
                }
            }
            SettingsCard(title: lang.l("settings.import")) {
                filledButton(lang.l("settings.import")) { importData() }
                filledButton(lang.l("settings.importMaccy")) { importFromMaccy() }
                filledButton(lang.l("settings.importAlfred")) { importFromAlfred() }
                if showImportSuccess {
                    captionText(lang.l("settings.importSuccess"), color: .green)
                }
            }
        }
    }

    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
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
            panel.allowedContentTypes = [.init(filenameExtension: "clipbackup") ?? .data]
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
            clipboardManager.replaceHistoryForImport(with: merged)
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
            clipboardManager.replaceHistoryForImport(with: merged)
            showImportSuccess = true; importExportError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showImportSuccess = false }
        } catch { importExportError = error.localizedDescription }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "clipbackup") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let merged = try makeDataPortService().importBackup(from: url, existingItems: clipboardManager.items, mode: .merge)
            clipboardManager.replaceHistoryForImport(with: merged)
            showImportSuccess = true
            importExportError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showImportSuccess = false }
        } catch {
            importExportError = error.localizedDescription
        }
    }
}

struct SettingsAboutSectionPanel: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showClearConfirm = false

    var body: some View {
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
}

// MARK: - Section Content

/// One settings section, shared between the embedded panel page and the
/// (optional) standalone window. `isInPanel` switches to the panel's visual
/// language: self-drawn rows on the vibrancy background instead of the system
/// grouped-form chrome.
struct SettingsSectionStack<Content: View>: View {
    let isInPanel: Bool
    @ViewBuilder let content: () -> Content

    init(isInPanel: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isInPanel = isInPanel
        self.content = content
    }

    var body: some View {
        if isInPanel {
            VStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        } else {
            Form { content() }
                .formStyle(.grouped)
        }
    }
}

/// A single settings row: label on the left, control on the right — mirrors
/// the main panel's row anatomy (12–13pt text, quiet secondary captions).
struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: DesignSystem.FontSize.body))
                if let caption {
                    Text(caption)
                        .font(.system(size: DesignSystem.FontSize.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

/// A full-width titled group of settings rows (panel style).
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let title {
                Text(title)
                    .font(.system(size: DesignSystem.FontSize.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 6) {
                content()
            }
        }
    }
}
