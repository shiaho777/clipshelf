import SwiftUI
import AppKit

struct DiffViewerSheet: View {
    @ObservedObject private var lang = LanguageManager.shared
    let itemA: ClipboardItem
    let itemB: ClipboardItem
    @Environment(\.popupWindowDismiss) private var dismissPopup

    private var hunks: [DiffHunk] {
        DiffEngine.diff(old: itemA.content, new: itemB.content)
    }

    private var deletionCount: Int {
        hunks.filter { if case .delete = $0.operation { return true }; return false }.count
    }
    private var insertionCount: Int {
        hunks.filter { if case .insert = $0.operation { return true }; return false }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────
            SheetHeader(lang.l("diff.title"), onClose: { dismissPopup() })

            // ── Diff lines ──────────────────────────────────────
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                        DiffLineView(hunk: hunk)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 200, maxHeight: 380)

            // ── Footer ──────────────────────────────────────────
            SheetFooter {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Label("\(insertionCount)", systemImage: "plus")
                        .font(.system(size: DesignSystem.FontSize.caption, weight: .medium))
                        .foregroundColor(.green)
                    Label("\(deletionCount)", systemImage: "minus")
                        .font(.system(size: DesignSystem.FontSize.caption, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                Spacer()
                Button(lang.l("diff.copy")) { copyDiffToClipboard() }
                    .font(.system(size: DesignSystem.FontSize.caption, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
        }
        .standardPopupLayout()
    }

    // MARK: - Actions

    private func copyDiffToClipboard() {
        let diffText = hunks.map { hunk -> String in
            switch hunk.operation {
            case .equal(let l):  return "  " + l
            case .insert(let l): return "+ " + l
            case .delete(let l): return "- " + l
            }
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diffText, forType: .string)
    }
}

// MARK: - Line View

private struct DiffLineView: View {
    let hunk: DiffHunk

    var body: some View {
        HStack(spacing: 0) {
            // Gutter indicator
            Text(gutterChar)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(gutterColor)
                .frame(width: 22, alignment: .center)
                .padding(.vertical, 2)

            // Line content
            Text(hunk.line.isEmpty ? " " : hunk.line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 6)
        .background(backgroundColor)
    }

    private var gutterChar: String {
        switch hunk.operation {
        case .equal:  return " "
        case .insert: return "+"
        case .delete: return "−"
        }
    }

    private var backgroundColor: Color {
        switch hunk.operation {
        case .equal:  return .clear
        case .insert: return Color.green.opacity(0.10)
        case .delete: return Color.red.opacity(0.10)
        }
    }

    private var textColor: Color {
        switch hunk.operation {
        case .equal:  return .primary.opacity(0.80)
        case .insert: return Color.green
        case .delete: return Color.red.opacity(0.88)
        }
    }

    private var gutterColor: Color {
        switch hunk.operation {
        case .equal:  return Color(NSColor.tertiaryLabelColor)
        case .insert: return Color.green
        case .delete: return Color.red.opacity(0.88)
        }
    }
}
