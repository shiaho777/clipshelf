import AppKit
import SwiftUI
import Combine

@MainActor
final class UserNotifier: ObservableObject {
    enum Kind {
        case info
        case warning
    }

    struct Notice: Equatable {
        let message: String
        let kind: Kind
        let createdAt: Date
    }

    static let shared = UserNotifier()

    @Published private(set) var latest: Notice?
    private var dismissTask: Task<Void, Never>?
    private var badgeRestore: (() -> Void)?

    private init() {}

    func setBadgeRestore(_ restore: @escaping () -> Void) {
        badgeRestore = restore
    }

    func show(_ message: String, kind: Kind = .info, duration: TimeInterval = 4.0) {
        let notice = Notice(message: message, kind: kind, createdAt: Date())
        latest = notice
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.latest == notice {
                self.latest = nil
            }
        }
        if kind == .warning {
            StatusItemController.shared.showWarningBadge(message) { [weak self] in
                self?.badgeRestore?()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        latest = nil
    }
}

struct AccessibilityPermissionBanner: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var isTrusted = AXIsProcessTrusted()

    var body: some View {
        if !isTrusted {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text(lang.l("permission.banner.message"))
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer(minLength: 4)
                Button(lang.l("permission.banner.openSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
                isTrusted = AXIsProcessTrusted()
            }
        }
    }
}

struct NoticeBanner: View {
    @ObservedObject private var notifier = UserNotifier.shared
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        if let notice = notifier.latest {
            HStack(spacing: 6) {
                Image(systemName: notice.kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(notice.kind == .warning ? .orange : .accentColor)
                Text(notice.message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer(minLength: 4)
                Button {
                    notifier.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((notice.kind == .warning ? Color.orange : Color.accentColor).opacity(0.1))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityLabel(notice.message)
        }
    }
}