import Foundation
import AppKit
import ImageIO
import os

struct PreparedClipboardImage {
    let hash: String
    let fileName: String?
    let inlineData: Data?
    let saveError: String?
}

struct ClipboardImagePasteboardPayload {
    let type: NSPasteboard.PasteboardType
    let data: Data?
    let dataProvider: NSPasteboardItemDataProvider?
}

final class ClipboardImagePasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let fileName: String
    private let fileURL: URL

    init(fileName: String, fileURL: URL) {
        self.fileName = fileName
        self.fileURL = fileURL
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let data = ImageCache.shared.data(for: fileName, loader: {
            try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }) else { return }
        item.setData(data, forType: type)
    }
}

private enum ClipboardImageStoragePreparation {
    static let compressionThreshold = 2 * 1024 * 1024

    static func storedRepresentation(of data: Data, fileExtension: String?) -> (Data, String) {
        if let ext = normalizedImageExtension(fileExtension) {
            return (data, ext)
        }
        guard data.count > compressionThreshold,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return (data, "png")
        }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData, "public.jpeg" as CFString, 1, nil
        ) else { return (data, "png") }
        CGImageDestinationAddImage(
            dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return (data, "png") }
        let jpegData = mutableData as Data
        guard jpegData.count < data.count else { return (data, "png") }
        return (jpegData, "jpg")
    }

    static func normalizedImageExtension(_ fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        switch fileExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif":
            return fileExtension.lowercased() == "jpeg" ? "jpg" : fileExtension.lowercased()
        default:
            return nil
        }
    }
}

/// Manages image persistence, caching, OCR, and migration.
/// Extracted from ClipboardManager to reduce its responsibilities.
@MainActor
final class ClipboardImageManager {
    private let imageStore: ClipboardImageStore
    private let ocrService: OCRServiceProtocol
    private let imagePrefetchQueue = DispatchQueue(label: "ClipShelf.imagePrefetch", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "ImageManager")

    init(imageStore: ClipboardImageStore, ocrService: OCRServiceProtocol) {
        self.imageStore = imageStore
        self.ocrService = ocrService
    }

    // MARK: - Resolve

    func resolvedImage(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image else { return nil }
        if let data = imageData(for: item) {
            return ImageCache.shared.image(for: item.id, data: data, fileName: item.imageFileName)
        }
        return nil
    }

    func imageData(for item: ClipboardItem) -> Data? {
        if let inlineData = item.imageData { return inlineData }
        guard let fileName = item.imageFileName else { return nil }
        return ImageCache.shared.data(for: fileName) { [imageStore] in
            imageStore.imageData(for: fileName)
        }
    }

    func imageDataForOCR(for item: ClipboardItem) async -> Data? {
        if let inlineData = item.imageData { return inlineData }
        guard let fileName = item.imageFileName else { return nil }
        if imageStore is FileClipboardImageStore {
            let url = imageStore.fileURL(for: fileName)
            return await Task.detached(priority: .utility) {
                ImageCache.shared.data(for: fileName) {
                    try? Data(contentsOf: url, options: [.mappedIfSafe])
                }
            }.value
        }
        return imageData(for: item)
    }

    func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imageStore.fileURL(for: fileName)
    }

    func pasteboardPayload(for item: ClipboardItem) -> ClipboardImagePasteboardPayload? {
        guard item.type == .image else { return nil }
        let type = pasteboardType(for: item)
        if let inlineData = item.imageData {
            return ClipboardImagePasteboardPayload(type: type, data: inlineData, dataProvider: nil)
        }
        guard let fileName = item.imageFileName else { return nil }
        if imageStore is FileClipboardImageStore {
            let provider = ClipboardImagePasteboardDataProvider(fileName: fileName, fileURL: imageStore.fileURL(for: fileName))
            return ClipboardImagePasteboardPayload(type: type, data: nil, dataProvider: provider)
        }
        guard let data = imageData(for: item) else { return nil }
        return ClipboardImagePasteboardPayload(type: type, data: data, dataProvider: nil)
    }

    private func pasteboardType(for item: ClipboardItem) -> NSPasteboard.PasteboardType {
        let ext = item.imageFileName.flatMap { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        if ext == "jpg" || ext == "jpeg" {
            return NSPasteboard.PasteboardType("public.jpeg")
        }
        if ext == "heic" || ext == "heif" {
            return NSPasteboard.PasteboardType("public.heic")
        }
        return .png
    }

    func thumbnail(for item: ClipboardItem, maxPixelSize: Int = 160) -> NSImage? {
        if let fileName = item.imageFileName {
            return ImageCache.shared.thumbnail(for: fileName, maxPixelSize: maxPixelSize) { [imageStore] in
                imageStore.imageData(for: fileName)
            }
        }
        guard let data = item.imageData else { return nil }
        return ImageCache.shared.thumbnail(for: item.id.uuidString, maxPixelSize: maxPixelSize) {
            data
        }
    }

    // MARK: - Save / Delete

    func saveImageFile(_ data: Data, fileExtension: String? = nil) -> (fileName: String?, inlineData: Data?) {
        let (finalData, ext) = ClipboardImageStoragePreparation.storedRepresentation(of: data, fileExtension: fileExtension)
        let fileName = "\(UUID().uuidString).\(ext)"
        do {
            try imageStore.saveImageData(finalData, fileName: fileName)
            return (fileName, nil)
        } catch {
            logger.error("Failed to save image file: \(error.localizedDescription)")
            return (nil, data)
        }
    }

    func prepareImageFile(_ data: Data, fileExtension: String? = nil) async -> PreparedClipboardImage {
        let imageStore = imageStore
        let prepared = await Task.detached(priority: .userInitiated) {
            let hash = ClipboardItem.hash(for: data)
            let (finalData, ext) = ClipboardImageStoragePreparation.storedRepresentation(of: data, fileExtension: fileExtension)
            let fileName = "\(UUID().uuidString).\(ext)"
            do {
                try imageStore.saveImageData(finalData, fileName: fileName)
                return PreparedClipboardImage(hash: hash, fileName: fileName, inlineData: nil, saveError: nil)
            } catch {
                return PreparedClipboardImage(hash: hash, fileName: nil, inlineData: data, saveError: error.localizedDescription)
            }
        }.value
        if let saveError = prepared.saveError {
            logger.error("Failed to save image file: \(saveError)")
        }
        return prepared
    }

    func cacheImage(id: UUID, data: Data, fileName: String?) {
        _ = ImageCache.shared.image(for: id, data: data, fileName: fileName)
    }

    func deleteImageFile(for item: ClipboardItem, remainingItems: [ClipboardItem]) {
        guard let fileName = item.imageFileName else {
            ImageCache.shared.remove(item.id)
            return
        }
        let hasOtherReferences = remainingItems.contains { $0.id != item.id && $0.imageFileName == fileName }
        deleteImageFile(for: item, hasOtherReferences: hasOtherReferences)
    }

    func deleteImageFile(for item: ClipboardItem, hasOtherReferences: Bool) {
        guard let fileName = item.imageFileName else {
            ImageCache.shared.remove(item.id)
            return
        }
        if !hasOtherReferences {
            imageStore.deleteImageFile(named: fileName)
        }
        ImageCache.shared.remove(item.id, fileName: fileName, removeSharedImage: !hasOtherReferences)
    }

    // MARK: - Maintenance

    func pruneOrphanedFiles(referencedFileNames: Set<String>) {
        imageStore.pruneOrphanedFiles(referencedFileNames: referencedFileNames)
    }

    // MARK: - OCR

    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        ocrService.recognizeText(in: imageData, completion: completion)
    }

    /// Async wrapper for OCR text recognition.
    func recognizeText(in imageData: Data) async -> String? {
        await ocrService.recognizeText(in: imageData)
    }

    // MARK: - Legacy Migration

    @discardableResult
    func migrateLegacyInlineImages(items: inout [ClipboardItem]) -> Bool {
        var migrated = false
        for i in items.indices where items[i].type == .image && items[i].imageData != nil && items[i].imageFileName == nil {
            guard let data = items[i].imageData else { continue }
            let fileName = "\(items[i].id.uuidString).png"
            let fileURL = imageStore.fileURL(for: fileName)
            do {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try imageStore.saveImageData(data, fileName: fileName)
                }
                items[i].imageFileName = fileName
                if items[i].imageHash == nil { items[i].imageHash = ClipboardItem.hash(for: data) }
                items[i].imageData = nil
                migrated = true
            } catch {
                logger.error("Failed to migrate legacy image \(fileName): \(error.localizedDescription)")
            }
        }
        return migrated
    }
}
