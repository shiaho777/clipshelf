import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

enum ClipboardDragSession {
    static var sourceItemID: UUID?
    static var isActive = false

    static func begin(id: UUID) {
        sourceItemID = id
        isActive = true
    }

    static func end() {
        sourceItemID = nil
        isActive = false
    }
}

struct ClipboardItemRow: View {

    let item: ClipboardItem
    var image: NSImage? = nil
    var imageURL: URL? = nil
    var index: Int? = nil
    var isFocused: Bool = false
    let onCopy: (Bool) -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onPreview: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onTransform: ((String) -> Void)? = nil
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var highlightIndices: Set<Int>? = nil
    // Use LanguageManager.shared directly instead of @ObservedObject to avoid
    // every row subscribing to language changes — language only changes at app
    // startup or via Settings, not during scrolling.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether this sensitive item has been unlocked in the current panel session.
    /// Managed by the parent view (MenuBarView) via `unlockedItemIDs` so the state
    /// survives LazyVStack row recycling when the user scrolls.
    var isUnlocked: Bool = false
    var onUnlock: (() -> Void)? = nil
    var onHoverChange: ((Bool) -> Void)? = nil
    var onReorder: ((UUID, Bool) -> Void)? = nil
    var filePaths: [String] = []
    @State private var loadedImage: NSImage?
    @State private var isCode: Bool = false
    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false

    var body: some View {
        let detection = item.detection
        
        HStack(spacing: 8) {
            if let idx = index {
                Text("⌘\(idx)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .frame(width: 24)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange.opacity(0.75))
            }
            
            // Color swatch with format cycling
            if detection.color != nil {
                ColorSwatchView(detection: detection)
            }
            
            // Content
            if item.isSensitive && !isUnlocked {
                // ── Sensitive lock placeholder ──────────────────
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.shared.l("item.sensitive.title"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(LanguageManager.shared.l("item.sensitive.unlockHint"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if item.type == .image {
                if let nsImage = loadedImage ?? image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 72, height: 52)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(LanguageManager.shared.l("item.image"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if item.isScreenshot {
                            TagBadge(
                                LanguageManager.shared.l("item.screenshot"),
                                systemImage: "camera.viewfinder",
                                color: .blue
                            )
                        }
                    }
                    TimeAgoText(date: item.timestamp)
                }
            } else if item.type == .fileURL {
                let paths = item.filePaths
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: item.isScreenshot ? "camera.viewfinder" : "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(item.isScreenshot ? .blue.opacity(0.75) : .orange.opacity(0.75))
                        Text(paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? item.content)
                            .lineLimit(1)
                            .font(.system(size: 12))
                        if paths.count > 1 {
                            TagBadge("+\(paths.count - 1)", color: .orange, fontSize: 9)
                        }
                        if item.isScreenshot {
                            TagBadge(LanguageManager.shared.l("item.screenshot"), color: .blue)
                        }
                    }
                    TimeAgoText(date: item.timestamp)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        highlightedDisplayText(item.displayText)
                            .lineLimit(2)
                            .font(.system(size: 12))
                        if item.type == .richText {
                            TagBadge("R", color: .blue)
                        }
                        if item.type == .text && isCode {
                            Image(systemName: "chevron.left.slash.chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.purple.opacity(0.6))
                        }
                        if detection.isURL {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue.opacity(0.6))
                        }
                        if detection.isFilePath {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange.opacity(0.6))
                        }
                    }
                    TimeAgoText(date: item.timestamp)
                }
            }

            Spacer(minLength: 4)
            
            // Action buttons
            if isHovered {
                HStack(spacing: 4) {
                    if detection.isURL {
                        rowActionButton(icon: "arrow.up.right.square", color: .blue.opacity(0.7)) {
                            if let url = detection.url { NSWorkspace.shared.open(url) }
                        }
                        .help(LanguageManager.shared.l("action.openURL"))
                    }
                        if detection.isFilePath {
                            rowActionButton(icon: "folder", color: .orange.opacity(0.7)) {
                                if let path = detection.filePath {
                                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                }
                            }
                            .help(LanguageManager.shared.l("action.openFinder"))
                        }
                        if item.type == .fileURL {
                            rowActionButton(icon: "folder", color: .orange.opacity(0.7)) {
                                if let first = item.filePaths.first {
                                    NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "")
                                }
                            }
                            .help(LanguageManager.shared.l("action.openFinder"))
                        }
                        if item.type != .image && item.type != .fileURL {
                            rowActionButton(icon: "pencil", color: .accentColor.opacity(0.7)) { onEdit?() }
                                .help(LanguageManager.shared.l("action.edit"))
                        }
                    rowActionButton(icon: "eye", color: .secondary.opacity(0.7)) { onPreview?() }
                        .help(LanguageManager.shared.l("action.preview"))
                    rowActionButton(icon: item.isPinned ? "pin.slash.fill" : "pin", color: .orange.opacity(0.7), action: onPin)
                    rowActionButton(icon: "trash", color: .red.opacity(0.6), action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            if isFocused {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 2.5)
                    .padding(.vertical, 5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isFocused
                        ? Color.accentColor.opacity(0.08)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovered = hovering
            }
            onHoverChange?(hovering)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .overlay(alignment: .top) {
            if isDropTargeted && ClipboardDragSession.sourceItemID != item.id {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .onTapGesture {
            if item.isSensitive && !isUnlocked {
                Task { @MainActor in
                    do {
                        try await BiometricAuthService.shared.authenticate(
                            reason: LanguageManager.shared.l("biometric.unlockSensitive")
                        )
                        onUnlock?()
                    } catch {
                        // Authentication failed or was cancelled — stay locked
                    }
                }
                return
            }
            if let onSelect {
                onSelect()
            } else {
                let optionPressed = NSEvent.modifierFlags.contains(.option)
                onCopy(optionPressed)
            }
        }
        .contextMenu {
            // Sensitive items: show Unlock when locked, normal actions when unlocked.
            if item.isSensitive && !isUnlocked {
                Button {
                    Task { @MainActor in
                        do {
                            try await BiometricAuthService.shared.authenticate(
                                reason: LanguageManager.shared.l("biometric.unlockSensitive")
                            )
                            onUnlock?()
                        } catch {}
                    }
                } label: {
                    Label(LanguageManager.shared.l("biometric.unlockSensitive"), systemImage: "lock.open")
                }
            } else {
            Button { onCopy(false) } label: {
                Label(LanguageManager.shared.l("action.copy"), systemImage: "doc.on.doc")
            }
            Button { onCopy(true) } label: {
                Label(LanguageManager.shared.l("action.pastePlain"), systemImage: "textformat")
            }
            if detection.isURL {
                Button {
                    if let url = detection.url { NSWorkspace.shared.open(url) }
                } label: {
                    Label(LanguageManager.shared.l("action.openURL"), systemImage: "arrow.up.right.square")
                }
            }
            if detection.isFilePath {
                Button {
                    if let path = detection.filePath {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Label(LanguageManager.shared.l("action.openFinder"), systemImage: "folder")
                }
            }
            if item.type == .fileURL {
                Button {
                    if let first = item.filePaths.first {
                        NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Label(LanguageManager.shared.l("action.openFinder"), systemImage: "folder")
                }
            }
            Button { onPreview?() } label: {
                Label(LanguageManager.shared.l("action.preview"), systemImage: "eye")
            }
            if item.type != .image && item.type != .fileURL {
                Button { onEdit?() } label: {
                    Label(LanguageManager.shared.l("action.edit"), systemImage: "pencil")
                }
            }
            Button { onPin() } label: {
                Label(item.isPinned ? LanguageManager.shared.l("action.unpin") : LanguageManager.shared.l("action.pin"), systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            if item.type != .image && item.type != .fileURL {
                Menu(LanguageManager.shared.l("action.transform")) {
                    ForEach(TextTransform.allCases, id: \.self) { transform in
                        Button(LanguageManager.shared.l(transform.localizationKey)) {
                            if let result = transform.apply(item.content) {
                                onTransform?(result)
                            }
                        }
                    }
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label(LanguageManager.shared.l("action.delete"), systemImage: "trash")
            }
            } // end sensitive else
        }
        .onDrag {
            ClipboardDragSession.begin(id: item.id)
            return makeDragProvider()
        } preview: {
            dragPreview
        }
        .onDrop(of: [.text, .plainText, .utf8PlainText, .image, .fileURL, .data], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .task(id: item.id) {
            // Cache code detection asynchronously to avoid blocking body rendering.
            if item.type == .text, !isCode {
                let content = item.content
                let result = await Task.detached(priority: .utility) {
                    PasteAdapterUtils.looksLikeCode(content)
                }.value
                isCode = result
            }
            guard item.type == .image, loadedImage == nil else { return }
            if let image {
                loadedImage = image
                return
            }
            guard let imageURL else { return }
            let fileName = imageURL.lastPathComponent
            let imageData = await Task.detached(priority: .utility) {
                ImageCache.shared.thumbnailData(for: fileName, maxPixelSize: 160) {
                    try? Data(contentsOf: imageURL, options: [.mappedIfSafe])
                }
            }.value
            loadedImage = imageData.flatMap(NSImage.init(data:))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(item.isPinned ? LanguageManager.shared.l("action.unpin") : LanguageManager.shared.l("action.pin"))
        .accessibilityIdentifier("clipboardItem-\(item.id.uuidString)")
    }


    private var dragPreview: some View {
        HStack(spacing: 8) {
            if item.type == .image, let nsImage = loadedImage ?? image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
            }
            Text(item.type == .image ? (item.ocrText ?? "Image") : String(item.content.prefix(48)))
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .frame(width: 180)
    }

    private func makeDragProvider() -> NSItemProvider {
        if item.isSensitive && !isUnlocked {
            return NSItemProvider(object: "" as NSString)
        }

        let provider: NSItemProvider
        switch item.type {
        case .text:
            provider = NSItemProvider(object: item.content as NSString)
            registerTextRepresentations(item.content, on: provider)
        case .richText:
            provider = NSItemProvider(object: item.content as NSString)
            registerTextRepresentations(item.content, on: provider)
            if let rtf = item.rtfData {
                let rtfData = rtf
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                    completion(rtfData, nil)
                    return nil
                }
            }
        case .image:
            provider = makeImageDragProvider()
        case .fileURL:
            provider = makeFileURLDragProvider()
        }

        provider.suggestedName = dragSuggestedName
        let sourceID = item.id
        provider.registerDataRepresentation(forTypeIdentifier: Self.reorderTypeID, visibility: .ownProcess) { completion in
            completion(sourceID.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    private func makeImageDragProvider() -> NSItemProvider {
        let fileURL = imageFileURLForDrag()
        let resolvedImage = loadedImage ?? image ?? loadImageForDrag()
        let provider: NSItemProvider

        // Prefer a concrete image object so rich-text / image destinations can accept it.
        // Also attach PNG/TIFF data and a real image-file representation for apps that
        // only accept filesystem images (Finder, Mail, many chat clients).
        if let img = resolvedImage {
            provider = NSItemProvider(object: img)
            registerImageDataRepresentations(for: img, fileURL: fileURL, on: provider)
        } else if let fileURL {
            let typeIdentifier = imageTypeIdentifier(for: fileURL)
            provider = NSItemProvider()
            registerImageFileRepresentation(fileURL: fileURL, typeIdentifier: typeIdentifier, on: provider)
            if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                let payload = data
                provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
                    completion(payload, nil)
                    return nil
                }
            }
        } else {
            return NSItemProvider()
        }

        if let fileURL {
            let typeIdentifier = imageTypeIdentifier(for: fileURL)
            registerImageFileRepresentation(fileURL: fileURL, typeIdentifier: typeIdentifier, on: provider)
        }
        return provider
    }

    private func registerImageDataRepresentations(for img: NSImage, fileURL: URL?, on provider: NSItemProvider) {
        if let fileURL, let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty {
            let typeIdentifier = imageTypeIdentifier(for: fileURL)
            let payload = fileData
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
                completion(payload, nil)
                return nil
            }
            if typeIdentifier != UTType.png.identifier {
                // Many destinations still prefer PNG even when the source is JPEG/HEIC.
                if let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let pngData = png
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                        completion(pngData, nil)
                        return nil
                    }
                }
            }
            return
        }

        if let tiff = img.tiffRepresentation {
            let tiffData = tiff
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
                completion(tiffData, nil)
                return nil
            }
            if let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let pngData = png
                provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(pngData, nil)
                    return nil
                }
            }
        }
    }

    private func registerImageFileRepresentation(fileURL: URL, typeIdentifier: String, on provider: NSItemProvider) {
        let stableURL = fileURL
        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            // Coordinated copies are safer for sandboxed receivers than in-place loads.
            completion(stableURL, true, nil)
            return nil
        }
    }

    private func imageTypeIdentifier(for fileURL: URL) -> String {
        UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.png.identifier
    }

    private func makeFileURLDragProvider() -> NSItemProvider {
        let paths = filePaths.isEmpty ? item.filePaths : filePaths
        guard let first = paths.first, FileManager.default.fileExists(atPath: first) else {
            let text = paths.isEmpty ? item.content : paths.joined(separator: "\n")
            let provider = NSItemProvider(object: text as NSString)
            registerTextRepresentations(text, on: provider)
            return provider
        }

        let firstURL = URL(fileURLWithPath: first)
        let provider = NSItemProvider(contentsOf: firstURL) ?? NSItemProvider(object: first as NSString)
        for path in paths.dropFirst() where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
                ?? UTType.data.identifier
            let stableURL = url
            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(stableURL, false, nil)
                return nil
            }
        }
        registerTextRepresentations(paths.joined(separator: "\n"), on: provider)
        return provider
    }

    private var dragSuggestedName: String {
        switch item.type {
        case .image:
            return item.imageFileName ?? "ClipShelf-Image.png"
        case .fileURL:
            return URL(fileURLWithPath: (filePaths.isEmpty ? item.filePaths : filePaths).first ?? "file").lastPathComponent
        default:
            let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "ClipShelf-Text" }
            return String(trimmed.prefix(32))
        }
    }

    private func registerTextRepresentations(_ text: String, on provider: NSItemProvider) {
        let data = text.data(using: .utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }

    private func loadImageForDrag() -> NSImage? {
        if let imageURL, let data = try? Data(contentsOf: imageURL), let img = NSImage(data: data) {
            return img
        }
        if let fileName = item.imageFileName {
            let url = AppStoragePaths.defaultStorageDirectory()
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                return img
            }
        }
        return nil
    }

    private func imageFileURLForDrag() -> URL? {
        if let imageURL, FileManager.default.fileExists(atPath: imageURL.path) {
            return imageURL
        }
        if let fileName = item.imageFileName {
            let url = AppStoragePaths.defaultStorageDirectory()
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static let reorderTypeID = "com.nicebro.clipshelf.item-id"

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let sourceID = ClipboardDragSession.sourceItemID, sourceID != item.id {
            ClipboardDragSession.end()
            onReorder?(sourceID, true)
            return true
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.reorderTypeID) }) {
            provider.loadDataRepresentation(forTypeIdentifier: Self.reorderTypeID) { data, _ in
                guard let data,
                      let raw = String(data: data, encoding: .utf8),
                      let sourceID = UUID(uuidString: raw),
                      sourceID != self.item.id
                else {
                    DispatchQueue.main.async { ClipboardDragSession.end() }
                    return
                }
                DispatchQueue.main.async {
                    ClipboardDragSession.end()
                    self.onReorder?(sourceID, true)
                }
            }
            return true
        }

        ClipboardDragSession.end()
        return false
    }

    private var accessibilityDescription: String {
        let typeDesc: String
        switch item.type {
        case .text: typeDesc = "Text"
        case .richText: typeDesc = "Rich text"
        case .image: typeDesc = "Image"
        case .fileURL: typeDesc = "File"
        }
        let pinned = item.isPinned ? ", pinned" : ""
        let sensitive = item.isSensitive ? ", sensitive" : ""
        let content = item.type == .image ? (item.ocrText ?? "image") : item.displayText
        return "\(typeDesc)\(pinned)\(sensitive): \(content)"
    }

    private func highlightedDisplayText(_ text: String) -> Text {
        guard let indices = highlightIndices, !indices.isEmpty else {
            return Text(text)
                .foregroundColor(.primary.opacity(0.88))
        }
        // Only highlight within the first 50 chars (displayText is already truncated).
        // This avoids O(n) Text concatenation for long content.
        let chars = Array(text)
        var result = Text("")
        var i = 0
        while i < chars.count {
            if indices.contains(i) {
                var end = i
                while end + 1 < chars.count && indices.contains(end + 1) { end += 1 }
                result = result + Text(String(chars[i...end]))
                    .foregroundColor(.accentColor)
                    .fontWeight(.semibold)
                i = end + 1
            } else {
                var end = i
                while end + 1 < chars.count && !indices.contains(end + 1) { end += 1 }
                result = result + Text(String(chars[i...end]))
                    .foregroundColor(.primary.opacity(0.88))
                i = end + 1
            }
        }
        return result
    }

    private func rowActionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowActionButtonStyle())
    }
}

private struct RowActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Color Swatch with Format Cycling
struct ColorSwatchView: View {
    let detection: ContentDetectionResult
    @State private var currentFormat: ColorFormat = .hex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        let formatString = detection.colorString(format: currentFormat) ?? ""
        
        Button(action: {
            let all = ColorFormat.allCases
            guard let i = all.firstIndex(of: currentFormat) else { return }
            let nextFormat = all[(i + 1) % all.count]
            let nextString = detection.colorString(format: nextFormat) ?? formatString
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(nextString, forType: .string)
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
                currentFormat = nextFormat
            }
        }) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: detection.color!))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Color(nsColor: detection.color!).opacity(0.25), radius: 2, y: 1)
                Text(formatString)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(LanguageManager.shared.l("action.colorCopy"))
    }
}

// MARK: - Shared tick publisher
// Internal so MenuBarView can subscribe once and pass `now` down to rows.
class TimeTickPublisher {
    static let shared = TimeTickPublisher()
    let publisher: AnyPublisher<Date, Never>
    private init() {
        publisher = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }
}

// MARK: - TimeAgoText
/// Renders a relative-time label.
/// Self-subscribes to TimeTickPublisher so time updates only re-render this
/// tiny label — not the entire parent view or list.
struct TimeAgoText: View {
    let date: Date
    @State private var now = Date()

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Text(Self.formatter.localizedString(for: date, relativeTo: now))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .onReceive(TimeTickPublisher.shared.publisher) { newNow in
                now = newNow
            }
    }
}
