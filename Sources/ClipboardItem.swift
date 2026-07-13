import Foundation
import AppKit
import CryptoKit

private final class FilePathCacheBox: NSObject {
    let paths: [String]

    init(_ paths: [String]) {
        self.paths = paths
    }
}

private enum ClipboardFilePathCache {
    private static let cache: NSCache<NSString, FilePathCacheBox> = {
        let cache = NSCache<NSString, FilePathCacheBox>()
        cache.countLimit = 4_096
        return cache
    }()

    static func paths(for content: String) -> [String] {
        let key = content as NSString
        if let cached = cache.object(forKey: key) {
            return cached.paths
        }
        let paths = parse(content)
        cache.setObject(FilePathCacheBox(paths), forKey: key)
        return paths
    }

    private static func parse(_ content: String) -> [String] {
        if content.first == "[",
           let data = content.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths
        }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var imageData: Data?
    var rtfData: Data?
    let type: ItemType
    var timestamp: Date
    var isPinned: Bool
    var useCount: Int
    var imageHash: String?
    var imageFileName: String?
    var ocrText: String?
    var sourceBundleID: String?
    var sourceAppName: String?
    var isSensitive: Bool
    var expiresAt: Date?
    /// True for system screenshots and screen recordings captured via `⌘⇧3/4/5`.
    var isScreenshot: Bool
    
    enum ItemType: String, Codable { case text, image, richText, fileURL }
    
    enum CodingKeys: String, CodingKey {
        case id, content, imageData, rtfData, type, timestamp, isPinned, useCount, imageHash, imageFileName, ocrText, sourceBundleID, sourceAppName, isSensitive, expiresAt, isScreenshot
    }
    
    init(id: UUID = UUID(), content: String = "", imageData: Data? = nil, rtfData: Data? = nil, type: ItemType = .text, timestamp: Date = Date(), isPinned: Bool = false, useCount: Int = 0, imageHash: String? = nil, imageFileName: String? = nil, ocrText: String? = nil, sourceBundleID: String? = nil, sourceAppName: String? = nil, isSensitive: Bool = false, expiresAt: Date? = nil, isScreenshot: Bool = false) {
        self.id = id
        self.content = content
        self.imageData = imageData
        self.rtfData = rtfData
        self.type = type
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.useCount = useCount
        self.imageHash = imageHash
        self.imageFileName = imageFileName
        self.ocrText = ocrText
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.isScreenshot = isScreenshot
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        type = try container.decode(ItemType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        isScreenshot = try container.decodeIfPresent(Bool.self, forKey: .isScreenshot) ?? false
        if imageFileName == nil {
            imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        } else {
            imageData = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(rtfData, forKey: .rtfData)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(useCount, forKey: .useCount)
        try container.encodeIfPresent(imageHash, forKey: .imageHash)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try container.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        if isSensitive { try container.encode(isSensitive, forKey: .isSensitive) }
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        if isScreenshot { try container.encode(isScreenshot, forKey: .isScreenshot) }
    }
    
    var displayText: String {
        let prefix = content.prefix(50)
        return prefix.endIndex == content.endIndex ? content : String(prefix) + "..."
    }
    
    var detection: ContentDetectionResult {
        (type == .image || type == .fileURL) ? .empty : ContentDetector.analyze(content)
    }

    var filePaths: [String] {
        guard type == .fileURL else { return [] }
        return ClipboardFilePathCache.paths(for: content)
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.imageData == rhs.imageData &&
        lhs.rtfData == rhs.rtfData && lhs.type == rhs.type && lhs.timestamp == rhs.timestamp &&
        lhs.isPinned == rhs.isPinned && lhs.useCount == rhs.useCount && lhs.imageHash == rhs.imageHash &&
        lhs.imageFileName == rhs.imageFileName && lhs.ocrText == rhs.ocrText &&
        lhs.sourceBundleID == rhs.sourceBundleID && lhs.sourceAppName == rhs.sourceAppName &&
        lhs.isSensitive == rhs.isSensitive && lhs.expiresAt == rhs.expiresAt &&
        lhs.isScreenshot == rhs.isScreenshot
    }
    
    static func hash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
