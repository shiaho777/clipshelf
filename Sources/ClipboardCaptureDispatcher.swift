import Foundation

@MainActor
final class ClipboardCaptureDispatcher {
    private let addText: (String, String?, String?, Bool, Date?, Bool) -> ClipboardItem
    private let addRichText: (String, Data, String?, String?, Bool, Date?, Bool) -> ClipboardItem
    private let addImage: (Data, String?, String?, String?, Bool, ((ClipboardItem) -> Void)?) -> Void
    private let addFileURL: ([String], String?, String?, Bool, Date?, Bool, Bool) -> ClipboardItem

    init(
        addText: @escaping (String, String?, String?, Bool, Date?, Bool) -> ClipboardItem,
        addRichText: @escaping (String, Data, String?, String?, Bool, Date?, Bool) -> ClipboardItem,
        addImage: @escaping (Data, String?, String?, String?, Bool, ((ClipboardItem) -> Void)?) -> Void,
        addFileURL: @escaping ([String], String?, String?, Bool, Date?, Bool, Bool) -> ClipboardItem
    ) {
        self.addText = addText
        self.addRichText = addRichText
        self.addImage = addImage
        self.addFileURL = addFileURL
    }

    func dispatch(
        _ content: CapturedContent,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        autoPin: Bool = false
    ) {
        let shouldEnqueue = PasteQueue.shared.stackMode && !isSensitive

        switch content.kind {
        case .text(let text):
            let item = addText(
                text,
                content.sourceBundleID,
                content.sourceAppName,
                isSensitive,
                expiresAt,
                autoPin
            )
            if shouldEnqueue { PasteQueue.shared.enqueue(item) }
        case .richText(let text, let rtfData):
            let item = addRichText(
                text,
                rtfData,
                content.sourceBundleID,
                content.sourceAppName,
                isSensitive,
                expiresAt,
                autoPin
            )
            if shouldEnqueue { PasteQueue.shared.enqueue(item) }
        case .image(let data):
            addImage(
                data,
                content.sourceBundleID,
                content.sourceAppName,
                nil,
                content.isScreenshot
            ) { item in
                if PasteQueue.shared.stackMode { PasteQueue.shared.enqueue(item) }
            }
        case .imageFile(let data, let fileExtension):
            addImage(
                data,
                content.sourceBundleID,
                content.sourceAppName,
                fileExtension,
                content.isScreenshot
            ) { item in
                if PasteQueue.shared.stackMode { PasteQueue.shared.enqueue(item) }
            }
        case .fileURL(let paths):
            let item = addFileURL(
                paths,
                content.sourceBundleID,
                content.sourceAppName,
                isSensitive,
                expiresAt,
                autoPin,
                content.isScreenshot
            )
            if shouldEnqueue { PasteQueue.shared.enqueue(item) }
        }
    }
}
