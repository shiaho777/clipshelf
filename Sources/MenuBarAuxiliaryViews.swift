import SwiftUI
import AppKit

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

struct PreviewSheet: View {
    let item: ClipboardItem
    var image: NSImage? = nil
    var imageURL: URL? = nil
    var onPaste: ((ClipboardItem) -> Void)? = nil
    @Environment(\.popupWindowDismiss) private var dismissPopup
    @ObservedObject var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(lang.l("preview.title"), onClose: { dismissPopup() }) {
                SheetHeaderIconButton(
                    icon: "arrow.up.right.square",
                    help: lang.l("preview.openExternally")
                ) {
                    openExternally()
                }
            }

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
                RTFTextView(rtfData: rtfData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
            } else {
                if CodeHighlighter.detectLanguage(item.content) != nil,
                   PasteAdapterUtils.looksLikeCode(item.content) {
                    CodePreviewView(text: item.content)
                } else {
                    PlainTextPreview(text: item.content)
                }
            }

            SheetFooter {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    switch item.type {
                    case .image:
                        if let img = image {
                            pb.writeObjects([img])
                        }
                    case .fileURL:
                        let urls = item.filePaths.compactMap { URL(fileURLWithPath: $0) as NSURL }
                        if !urls.isEmpty {
                            pb.writeObjects(urls)
                        } else {
                            pb.setString(item.content, forType: .string)
                        }
                    case .richText:
                        if let rtf = item.rtfData {
                            pb.setData(rtf, forType: .rtf)
                        }
                        pb.setString(item.content, forType: .string)
                    default:
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
        .standardPopupLayout(size: WindowLayout.previewSize)
    }

    private func openExternally() {
        if item.isSensitive {
            Task { @MainActor in
                do {
                    try await BiometricAuthService.shared.authenticate(
                        reason: LanguageManager.shared.l("biometric.unlockSensitive")
                    )
                } catch {
                    return
                }
                openItemExternally()
            }
        } else {
            openItemExternally()
        }
    }

    private func openItemExternally() {
        let ws = NSWorkspace.shared
        var config = NSWorkspace.OpenConfiguration()
        config.activates = true
        switch item.type {
        case .image:
            if let url = imageURL, FileManager.default.fileExists(atPath: url.path) {
                ws.open(url, configuration: config, completionHandler: nil)
            } else if let img = image, let url = Self.writeTempImage(img) {
                ws.open(url, configuration: config, completionHandler: nil)
            }
        case .text:
            if let url = Self.writeTempText(item.content, fileExtension: "txt") {
                Self.openWithTextEdit([url], configuration: config)
            }
        case .richText:
            if let rtf = item.rtfData,
               let url = Self.writeTempData(rtf, fileExtension: "rtf") {
                Self.openWithTextEdit([url], configuration: config)
            } else if let url = Self.writeTempText(item.content, fileExtension: "txt") {
                Self.openWithTextEdit([url], configuration: config)
            }
        case .fileURL:
            let urls = item.filePaths
                .filter { FileManager.default.fileExists(atPath: $0) }
                .prefix(10)
                .map { URL(fileURLWithPath: $0) }
            for url in urls {
                ws.open(url, configuration: config, completionHandler: nil)
            }
        }
    }

    private static func openWithTextEdit(_ urls: [URL], configuration: NSWorkspace.OpenConfiguration) {
        if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open(urls, withApplicationAt: editor, configuration: configuration, completionHandler: nil)
        } else {
            for url in urls {
                NSWorkspace.shared.open(url, configuration: configuration, completionHandler: nil)
            }
        }
    }

    private static func previewTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            let cutoff = Date().addingTimeInterval(-86_400)
            for file in files {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        return dir
    }

    private static func writeTempData(_ data: Data, fileExtension: String) -> URL? {
        let url = previewTempDirectory()
            .appendingPathComponent("ClipShelf-\(UUID().uuidString.prefix(8)).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func writeTempText(_ text: String, fileExtension: String) -> URL? {
        guard let data = text.data(using: .utf8) else { return nil }
        return writeTempData(data, fileExtension: fileExtension)
    }

    private static func writeTempImage(_ nsImage: NSImage) -> URL? {
        guard let tiff = nsImage.tiffRepresentation else { return nil }
        return writeTempData(tiff, fileExtension: "tiff")
    }
}

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
        .standardPopupLayout(size: WindowLayout.editorSize)
        .onAppear { editedContent = item.content }
    }
}

struct BottomBarButton: View {
    let icon: String
    var tint: Color = .secondary
    var label: String? = nil
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(tint)
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(tint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, label == nil ? 0 : 6)
            .frame(height: 28)
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
