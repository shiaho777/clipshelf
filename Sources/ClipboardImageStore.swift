import Foundation

protocol ClipboardImageStore {
    func fileURL(for fileName: String) -> URL
    func imageData(for fileName: String) -> Data?
    func saveImageData(_ data: Data, fileName: String) throws
    func deleteImageFile(named fileName: String)
    func pruneOrphanedFiles(referencedFileNames: Set<String>)
}

final class FileClipboardImageStore: ClipboardImageStore {
    private let directoryURL: URL
    
    init(storageDirectory: URL) {
        directoryURL = storageDirectory.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        ImageCache.shared.configureThumbnailDiskCache(directory: directoryURL.appendingPathComponent("thumbnails", isDirectory: true))
    }
    
    func fileURL(for fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }
    
    func imageData(for fileName: String) -> Data? {
        let fileURL = fileURL(for: fileName)
        return ImageCache.shared.data(for: fileName) {
            try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }
    }
    
    func saveImageData(_ data: Data, fileName: String) throws {
        try data.write(to: fileURL(for: fileName))
        _ = ImageCache.shared.data(for: fileName) { data }
    }
    
    func deleteImageFile(named fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
        ImageCache.shared.removeShared(fileName: fileName)
    }
    
    func pruneOrphanedFiles(referencedFileNames: Set<String>) {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for fileURL in fileURLs where fileURL.lastPathComponent != "thumbnails" && !referencedFileNames.contains(fileURL.lastPathComponent) {
            try? FileManager.default.removeItem(at: fileURL)
            ImageCache.shared.removeShared(fileName: fileURL.lastPathComponent)
        }
    }
}
