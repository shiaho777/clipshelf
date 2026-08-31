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
    @State private var section = 0

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
                clipboardManagerView.generalSectionInPanel
            case 1:
                clipboardManagerView.rulesSectionInPanel
            case 2:
                clipboardManagerView.dataSectionInPanel
            default:
                clipboardManagerView.aboutSectionInPanel
            }
        }
    }

    /// `SettingsView` is instantiated purely to host the section builders;
    /// its body is never rendered in this mode.
    private var clipboardManagerView: SettingsView {
        SettingsView(clipboardManager: clipboardManager, snippetManager: snippetManager)
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
