import SwiftUI

/// Settings rendered inside the main panel (no separate window).
/// A header with a back button and a segmented picker switches between the
/// same four sections `SettingsView` shows in its window variant.
struct SettingsEmbeddedView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    var onBack: () -> Void

    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header: back button + section picker
            HStack(spacing: 8) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(LanguageManager.shared.l("button.back"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.shared.l("button.back"))

                Picker("", selection: $section) {
                    Text(LanguageManager.shared.l("settings.tab.general")).tag(0)
                    Text(LanguageManager.shared.l("settings.tab.rules")).tag(1)
                    Text(LanguageManager.shared.l("settings.tab.data")).tag(2)
                    Text(LanguageManager.shared.l("settings.tab.about")).tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 14)
            // fullSizeContentView: keep clear of the transparent titlebar
            .padding(.top, 36)
            .padding(.bottom, 10)

            SettingsView(
                clipboardManager: clipboardManager,
                snippetManager: snippetManager,
                initialTab: section,
                showsOwnHeader: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(section)
        }
        .transition(.opacity)
    }
}
