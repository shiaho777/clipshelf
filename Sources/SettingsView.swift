import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var lang = LanguageManager.shared
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    var onOpenSnippets: () -> Void = {}
    
    var body: some View {
        Form {
            Section(lang.l("settings.general")) {
                Toggle(lang.l("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in setLaunchAtLogin(launchAtLogin) }
                Picker(lang.l("settings.language"), selection: $lang.language) {
                    Text(lang.l("language.zh")).tag("zh")
                    Text(lang.l("language.en")).tag("en")
                }
                HotKeyRecorderView(hotKey: $hotKeyManager.mainHotKey)
            }
            Section(lang.l("snippets.title")) {
                HStack {
                    Text(lang.l("snippets.desc"))
                    Spacer()
                    Button(lang.l("snippets.manage")) { onOpenSnippets() }
                }
            }
            Section(lang.l("settings.data")) {
                HStack {
                    Text(lang.l("settings.records", clipboardManager.items.count))
                    Spacer()
                    Button(lang.l("button.clear")) { clipboardManager.clearAll() }
                }
                HStack {
                    Button(lang.l("data.export")) { exportData() }
                    Spacer()
                    Button(lang.l("data.import")) { importData() }
                }
            }
            Section(lang.l("settings.about")) {
                Text("ClipboardManager v1.1").foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 380)
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
    
    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ClipboardManager_Backup.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DataExporter.shared.exportAll(to: url)
        }
    }
    
    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DataExporter.shared.importAll(from: url, clipboardManager: clipboardManager)
        }
    }
}
