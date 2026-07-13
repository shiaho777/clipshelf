import Foundation
import AppKit
import ImageIO
import CryptoKit

class ImageCache {
    static let shared = ImageCache()
    private let itemCache = NSCache<NSString, NSImage>()
    private let sharedFileCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let thumbnailDataCache = NSCache<NSString, NSData>()
    private let sharedDataCache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var thumbnailKeysByFileName: [String: Set<String>] = [:]
    private var thumbnailDiskCacheDirectory: URL?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    init() {
        itemCache.countLimit = 600
        itemCache.totalCostLimit = 192 * 1024 * 1024
        sharedFileCache.countLimit = 600
        sharedFileCache.totalCostLimit = 192 * 1024 * 1024
        thumbnailCache.countLimit = 2_000
        thumbnailCache.totalCostLimit = 128 * 1024 * 1024
        thumbnailDataCache.countLimit = 2_000
        thumbnailDataCache.totalCostLimit = 64 * 1024 * 1024
        sharedDataCache.countLimit = 300
        sharedDataCache.totalCostLimit = 128 * 1024 * 1024
        
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.clearAll()
        }
        memoryPressureSource?.resume()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    func clearAll() {
        itemCache.removeAllObjects()
        sharedFileCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        thumbnailDataCache.removeAllObjects()
        sharedDataCache.removeAllObjects()
        lock.withLock {
            thumbnailKeysByFileName.removeAll(keepingCapacity: true)
        }
    }

    func configureThumbnailDiskCache(directory: URL?) {
        lock.withLock {
            thumbnailDiskCacheDirectory = directory
        }
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    
    func image(for id: UUID, data: Data?, fileName: String? = nil) -> NSImage? {
        let key = id.uuidString as NSString
        if let cached = itemCache.object(forKey: key) { return cached }
        if let fileName, let shared = sharedFileCache.object(forKey: fileName as NSString) {
            itemCache.setObject(shared, forKey: key)
            return shared
        }
        guard let data else { return nil }
        if let fileName {
            sharedDataCache.setObject(data as NSData, forKey: fileName as NSString)
        }
        guard let img = NSImage(data: data) else { return nil }
        let cost = data.count
        itemCache.setObject(img, forKey: key, cost: cost)
        if let fileName {
            sharedFileCache.setObject(img, forKey: fileName as NSString, cost: cost)
        }
        return img
    }
    
    func image(for id: UUID, fileName: String, dataLoader: () -> Data?) -> NSImage? {
        let idKey = id.uuidString as NSString
        if let cached = itemCache.object(forKey: idKey) { return cached }
        let fileKey = fileName as NSString
        if let shared = sharedFileCache.object(forKey: fileKey) {
            itemCache.setObject(shared, forKey: idKey)
            return shared
        }
        guard let data = data(for: fileName, loader: dataLoader) else { return nil }
        return image(for: id, data: data, fileName: fileName)
    }

    func cachedSharedImage(for fileName: String) -> NSImage? {
        sharedFileCache.object(forKey: fileName as NSString)
    }

    func thumbnail(for fileName: String, maxPixelSize: Int, dataLoader: () -> Data?) -> NSImage? {
        let cacheKey = "\(fileName)#thumb#\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        guard let data = data(for: fileName, loader: dataLoader),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: cacheKey, cost: cgImage.bytesPerRow * cgImage.height)
        _ = lock.withLock {
            thumbnailKeysByFileName[fileName, default: []].insert(cacheKey as String)
        }
        return image
    }

    func thumbnailData(for fileName: String, maxPixelSize: Int, dataLoader: () -> Data?) -> Data? {
        let cacheKey = "\(fileName)#thumb#\(maxPixelSize)" as NSString
        if let cached = thumbnailDataCache.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }
        if let diskData = loadThumbnailDataFromDisk(fileName: fileName, maxPixelSize: maxPixelSize) {
            thumbnailDataCache.setObject(diskData as NSData, forKey: cacheKey, cost: diskData.count)
            _ = lock.withLock {
                thumbnailKeysByFileName[fileName, default: []].insert(cacheKey as String)
            }
            return diskData
        }
        guard let data = data(for: fileName, loader: dataLoader),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let result = output as Data
        thumbnailDataCache.setObject(result as NSData, forKey: cacheKey, cost: result.count)
        saveThumbnailDataToDisk(result, fileName: fileName, maxPixelSize: maxPixelSize)
        _ = lock.withLock {
            thumbnailKeysByFileName[fileName, default: []].insert(cacheKey as String)
        }
        return result
    }
    
    private func loadThumbnailDataFromDisk(fileName: String, maxPixelSize: Int) -> Data? {
        guard let url = thumbnailDiskFileURL(fileName: fileName, maxPixelSize: maxPixelSize, createDirectory: false) else {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func saveThumbnailDataToDisk(_ data: Data, fileName: String, maxPixelSize: Int) {
        guard let url = thumbnailDiskFileURL(fileName: fileName, maxPixelSize: maxPixelSize, createDirectory: true) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func thumbnailDiskFileURL(fileName: String, maxPixelSize: Int, createDirectory: Bool) -> URL? {
        guard let root = lock.withLock({ thumbnailDiskCacheDirectory }) else {
            return nil
        }
        let directory = root.appendingPathComponent(Self.diskKey(for: fileName), isDirectory: true)
        if createDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(maxPixelSize).png")
    }

    private static func diskKey(for value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func data(for fileName: String, loader: () -> Data?) -> Data? {
        let key = fileName as NSString
        if let cached = sharedDataCache.object(forKey: key) {
            return Data(referencing: cached)
        }
        guard let loaded = loader() else { return nil }
        sharedDataCache.setObject(loaded as NSData, forKey: key, cost: loaded.count)
        return loaded
    }
    
    func remove(_ id: UUID, fileName: String? = nil, removeSharedImage: Bool = false) {
        itemCache.removeObject(forKey: id.uuidString as NSString)
        guard removeSharedImage, let fileName else { return }
        removeShared(fileName: fileName)
    }
    
    func removeShared(fileName: String) {
        let key = fileName as NSString
        sharedFileCache.removeObject(forKey: key)
        sharedDataCache.removeObject(forKey: key)
        let thumbnailKeys = lock.withLock { thumbnailKeysByFileName.removeValue(forKey: fileName) ?? [] }
        for key in thumbnailKeys {
            thumbnailCache.removeObject(forKey: key as NSString)
            thumbnailDataCache.removeObject(forKey: key as NSString)
        }
        if let root = lock.withLock({ thumbnailDiskCacheDirectory }) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.diskKey(for: fileName), isDirectory: true))
        }
    }
}
