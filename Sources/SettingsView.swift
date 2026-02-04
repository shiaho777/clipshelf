import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var lang = LanguageManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section(lang.l("settings.general")) {
                Toggle(lang.l("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in setLaunchAtLogin(launchAtLogin) }
                Picker(lang.l("settings.language"), selection: $lang.language) {
                    Text(lang.l("language.zh")).tag("zh")
                    Text(lang.l("language.en")).tag("en")
                }
            }
            Section(lang.l("settings.data")) {
                HStack {
                    Text(lang.l("settings.records", clipboardManager.items.count))
                    Spacer()
                    Button(lang.l("button.clear")) { clipboardManager.clearAll() }
                }
            }
            Section(lang.l("settings.about")) {
                Text("ClipboardManager v1.0").foregroundColor(.secondary)
                Text(lang.l("settings.shortcut")).font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 280)
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
