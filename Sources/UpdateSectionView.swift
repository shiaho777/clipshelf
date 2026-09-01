import SwiftUI

/// The "Updates" block on the About page, shared by the in-panel settings and
/// the standalone settings window. Neutral styling to match the rest of the
/// settings UI: secondary text for status, one action per state, no icons.
struct UpdateSectionView: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                statusView
                Spacer(minLength: DesignSystem.Spacing.lg)
                actionView
            }

            if case .downloading(let fraction, let received, _, let speed) = checker.phase {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: fraction)
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: received, countStyle: .file))
                        Spacer()
                        Text(speedText(speed))
                    }
                    .font(.system(size: DesignSystem.FontSize.footnote))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            if case .ready = checker.phase {
                Text(lang.l("update.installHint"))
                    .font(.system(size: DesignSystem.FontSize.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    @ViewBuilder private var statusView: some View {
        Group {
            switch checker.phase {
            case .idle:
                EmptyView()
            case .checking:
                Text(lang.l("update.checking"))
                    .foregroundStyle(.secondary)
            case .upToDate:
                Text(lang.l("update.upToDate"))
                    .foregroundStyle(.secondary)
            case .available(let release):
                Text(release.version)
                    .font(.system(size: DesignSystem.FontSize.body, design: .monospaced))
            case .downloading(let fraction, _, _, _):
                Text("\(lang.l("update.downloading")) \(Int(fraction * 100))%")
                    .foregroundStyle(.secondary)
            case .ready:
                Text(lang.l("update.ready"))
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .font(.system(size: DesignSystem.FontSize.body))
    }

    @ViewBuilder private var actionView: some View {
        switch checker.phase {
        case .idle:
            Button(lang.l("update.check")) { checker.checkForUpdates() }
                .buttonStyle(.bordered)
                .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Button(lang.l("update.check")) { checker.checkForUpdates() }
                .buttonStyle(.plain)
                .font(.system(size: DesignSystem.FontSize.caption))
                .foregroundStyle(.secondary)
        case .available:
            Button(lang.l("update.download")) { checker.startDownload() }
                .buttonStyle(.borderedProminent)
                .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
        case .downloading:
            Button(lang.l("update.cancel")) { checker.cancelDownload() }
                .buttonStyle(.plain)
                .font(.system(size: DesignSystem.FontSize.caption))
                .foregroundStyle(.secondary)
        case .ready:
            Button(lang.l("update.install")) { checker.install() }
                .buttonStyle(.borderedProminent)
                .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
        case .failed:
            Button(lang.l("update.retry")) { checker.checkForUpdates() }
                .buttonStyle(.plain)
                .font(.system(size: DesignSystem.FontSize.caption))
                .foregroundStyle(.secondary)
        }
    }

    private func speedText(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file) + "/s"
    }
}
