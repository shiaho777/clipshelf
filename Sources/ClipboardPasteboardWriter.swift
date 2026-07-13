import Foundation
import AppKit

enum ClipboardPasteboardWriter {
    struct WriteResult {
        let smartPasteDescription: String?
        let retainedProviders: [NSPasteboardItemDataProvider]
    }

    static func write(
        item: ClipboardItem,
        to pasteboard: NSPasteboard,
        autoPaste: Bool,
        asPlainText: Bool,
        smartPasteEnabled: Bool,
        targetBundleID: String?,
        imagePayload: (() -> ClipboardImagePasteboardPayload?)?
    ) -> WriteResult {
        pasteboard.clearContents()
        var retainedProviders: [NSPasteboardItemDataProvider] = []
        var smartPasteDescription: String?

        if autoPaste, smartPasteEnabled, item.type != .image,
           let bundleID = targetBundleID,
           let payload = PasteAdapterManager.shared.adaptedPayload(
            for: bundleID,
            content: item.content,
            type: item.type
           ) {
            if let string = payload.string { pasteboard.setString(string, forType: .string) }
            if let rtf = payload.rtf { pasteboard.setData(rtf, forType: .rtf) }
            if let html = payload.html { pasteboard.setData(html, forType: .html) }
            smartPasteDescription = PasteAdapterManager.shared.adapterName(for: bundleID)
        } else if asPlainText, item.type != .image {
            pasteboard.setString(item.content, forType: .string)
        } else {
            switch item.type {
            case .image:
                if let payload = imagePayload?() {
                    if let provider = payload.dataProvider {
                        let pasteboardItem = NSPasteboardItem()
                        if pasteboardItem.setDataProvider(provider, forTypes: [payload.type]) {
                            retainedProviders.append(provider)
                            pasteboard.writeObjects([pasteboardItem])
                        }
                    } else if let data = payload.data {
                        pasteboard.setData(data, forType: payload.type)
                    }
                }
            case .richText:
                if let rtfData = item.rtfData { pasteboard.setData(rtfData, forType: .rtf) }
                pasteboard.setString(item.content, forType: .string)
            case .text:
                pasteboard.setString(item.content, forType: .string)
            case .fileURL:
                let fileURLs = item.filePaths.compactMap { URL(fileURLWithPath: $0) as NSURL }
                if !fileURLs.isEmpty { pasteboard.writeObjects(fileURLs) }
            }
        }

        return WriteResult(
            smartPasteDescription: smartPasteDescription,
            retainedProviders: retainedProviders
        )
    }
}
