import Foundation
import AppKit

enum ClipboardPasteboardWriter {
    struct WriteResult {
        let smartPasteDescription: String?
        let retainedProviders: [NSPasteboardItemDataProvider]
        /// False when nothing could be placed on the pasteboard (e.g. image
        /// payload unavailable). The pasteboard is left untouched in that
        /// case, so callers must not treat this as a successful copy.
        let didWrite: Bool
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
        var retainedProviders: [NSPasteboardItemDataProvider] = []
        var smartPasteDescription: String?

        // Resolve everything that can fail *before* clearing the pasteboard.
        // Clearing first and failing later would destroy the user's current
        // clipboard content while writing nothing in its place.

        if autoPaste, smartPasteEnabled, item.type != .image,
           let bundleID = targetBundleID,
           let payload = PasteAdapterManager.shared.adaptedPayload(
            for: bundleID,
            content: item.content,
            type: item.type
           ) {
            var wrote = false
            if payload.string != nil || payload.rtf != nil || payload.html != nil {
                pasteboard.clearContents()
                if let string = payload.string { wrote = pasteboard.setString(string, forType: .string) || wrote }
                if let rtf = payload.rtf { wrote = pasteboard.setData(rtf, forType: .rtf) || wrote }
                if let html = payload.html { wrote = pasteboard.setData(html, forType: .html) || wrote }
            }
            smartPasteDescription = PasteAdapterManager.shared.adapterName(for: bundleID)
            return WriteResult(
                smartPasteDescription: smartPasteDescription,
                retainedProviders: retainedProviders,
                didWrite: wrote
            )
        }

        if asPlainText, item.type != .image {
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
            return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: true)
        }

        switch item.type {
        case .image:
            guard let payload = imagePayload?() else {
                return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: false)
            }
            if let provider = payload.dataProvider {
                let pasteboardItem = NSPasteboardItem()
                guard pasteboardItem.setDataProvider(provider, forTypes: [payload.type]) else {
                    return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: false)
                }
                retainedProviders.append(provider)
                pasteboard.clearContents()
                pasteboard.writeObjects([pasteboardItem])
            } else if let data = payload.data {
                pasteboard.clearContents()
                guard pasteboard.setData(data, forType: payload.type) else {
                    return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: false)
                }
            } else {
                return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: false)
            }
        case .richText:
            pasteboard.clearContents()
            if let rtfData = item.rtfData { pasteboard.setData(rtfData, forType: .rtf) }
            pasteboard.setString(item.content, forType: .string)
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
        case .fileURL:
            let fileURLs = item.filePaths.compactMap { URL(fileURLWithPath: $0) as NSURL }
            guard !fileURLs.isEmpty else {
                return WriteResult(smartPasteDescription: nil, retainedProviders: [], didWrite: false)
            }
            pasteboard.clearContents()
            pasteboard.writeObjects(fileURLs)
        }

        return WriteResult(
            smartPasteDescription: smartPasteDescription,
            retainedProviders: retainedProviders,
            didWrite: true
        )
    }
}
