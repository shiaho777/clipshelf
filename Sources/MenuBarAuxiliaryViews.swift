import SwiftUI
import AppKit

// MARK: - RTF Preview (NSViewRepresentable)
/// Renders an RTF Data buffer using a native NSTextView inside a SwiftUI layout.
struct RTFTextView: NSViewRepresentable {
    let rtfData: Data

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        if let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        }
        // Fit text to scroll view width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        scrollView.documentView = textView
        if let container = textView.textContainer {
            container.widthTracksTextView = true
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        }
    }
}

// MARK: - Plain Text Preview (NSTextView for performance)
/// Renders plain text using NSTextView instead of SwiftUI Text.
/// SwiftUI Text performs O(n) layout measurement on every render, causing
/// severe lag with long content. NSTextView has native virtualization.
struct PlainTextPreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = {
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = 3
            return ps
        }()
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ])
        )
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        scrollView.documentView = textView
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.size = NSSize(width: scrollView.contentSize.width - 40, height: .greatestFiniteMagnitude)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ])
        )
    }
}

// MARK: - Preview Sheet
struct PreviewSheet: View {
    let item: ClipboardItem
    var image: NSImage? = nil
    var onPaste: ((ClipboardItem) -> Void)? = nil
    @Environment(\.popupWindowDismiss) private var dismissPopup
    @ObservedObject var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(lang.l("preview.title"), onClose: { dismissPopup() })

            if item.type == .image {
                if let img = image {
                    ScrollView {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                            .padding(20)
                    }
                } else {
                    // Image failed to load — show placeholder.
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text(lang.l("preview.imageFailed"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if item.type == .fileURL {
                // File URL preview: show file list with icons.
                VStack(alignment: .leading, spacing: 8) {
                    let paths = item.filePaths
                    ForEach(paths.prefix(20), id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    if paths.count > 20 {
                        Text(lang.l("list.loadMore", paths.count - 20))
                            .font(.system(size: DesignSystem.FontSize.caption))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if item.type == .richText, let rtfData = item.rtfData {
                // Native RTF rendering — preserves fonts, colours, and formatting.
                RTFTextView(rtfData: rtfData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
            } else {
                // Code syntax highlighting: detect code and render with colors.
                if CodeHighlighter.detectLanguage(item.content) != nil,
                   PasteAdapterUtils.looksLikeCode(item.content) {
                    CodePreviewView(text: item.content)
                } else {
                    // Use NSTextView for long text — SwiftUI Text is O(n) for layout
                    // and causes severe lag with 10k+ character content.
                    PlainTextPreview(text: item.content)
                }
            }

            // Action bar: copy + paste directly from preview.
            SheetFooter {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    if item.type == .image, let img = image {
                        pb.writeObjects([img])
                    } else {
                        pb.setString(item.content, forType: .string)
                    }
                    dismissPopup()
                } label: {
                    Label(lang.l("action.copy"), systemImage: "doc.on.doc")
                        .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button {
                    onPaste?(item)
                    dismissPopup()
                } label: {
                    Label(lang.l("action.paste"), systemImage: "arrow.right.doc.on.clipboard")
                        .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .standardPopupLayout()
    }
}

// MARK: - Code Preview (Syntax Highlighted)
struct CodePreviewView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let language = CodeHighlighter.detectLanguage(text) {
                HStack {
                    Image(systemName: "chevron.left.slash.chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))
            }
            CodeHighlightNSView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
        }
    }
}

struct CodeHighlightNSView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        CodeHighlighter.makeScrollView(for: text)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(CodeHighlighter.highlighted(text))
    }
}

// MARK: - Edit Sheet
struct EditSheet: View {
    let item: ClipboardItem
    @ObservedObject var clipboardManager: ClipboardManager
    var onSaveAndPaste: (() -> Void)? = nil
    @Environment(\.popupWindowDismiss) private var dismissPopup
    @ObservedObject var lang = LanguageManager.shared
    @State private var editedContent: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(lang.l("edit.title"), onClose: { dismissPopup() })

            TextEditor(text: $editedContent)
                .font(.system(size: DesignSystem.FontSize.body))
                .lineSpacing(3)
                .padding(DesignSystem.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .standardEditorSurface()

            SheetFooter {
                Button(lang.l("button.cancel")) { dismissPopup() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(lang.l("edit.saveAndPaste")) {
                    clipboardManager.updateItemContent(item, newContent: editedContent)
                    clipboardManager.copyToClipboard(
                        clipboardManager.item(byID: item.id) ?? item,
                        autoPaste: true
                    )
                    dismissPopup()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedContent.isEmpty)
            }
        }
        .standardPopupLayout()
        .onAppear { editedContent = item.content }
    }
}

// MARK: - Bottom Bar Button
struct BottomBarButton: View {
    let icon: String
    var tint: Color = .secondary
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
