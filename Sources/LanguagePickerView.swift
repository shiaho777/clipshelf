import SwiftUI

struct LanguagePickerView: View {
    var title: String? = nil
    var subtitle: String? = nil
    var showsCurrentSelection: Bool = false
    var onSelected: ((String) -> Void)? = nil

    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 20) {
            if let title {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(AppLanguageOption.all) { option in
                    languageButton(option)
                }
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func languageButton(_ option: AppLanguageOption) -> some View {
        let selected = showsCurrentSelection && lang.language == option.code
        return Button {
            lang.selectLanguage(option.code)
            onSelected?(option.code)
        } label: {
            HStack(spacing: 14) {
                Text(option.flag)
                    .font(.system(size: 28))
                    .frame(width: 36, height: 36)
                Text(option.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LanguageSwitcherButton: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(lang.currentOption.flag)
                    .font(.system(size: 14))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(lang.l("language.switch"))
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            LanguagePickerView(
                title: nil,
                subtitle: nil,
                showsCurrentSelection: true,
                onSelected: { _ in
                    showPicker = false
                }
            )
            .padding(.vertical, 14)
            .frame(width: 240)
        }
    }
}
