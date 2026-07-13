import SwiftUI
import AppKit

// MARK: - Content Detection Helpers
enum ColorFormat: CaseIterable {
    case hex, rgb, hsl
}

struct ContentDetectionResult {
    let trimmedText: String
    let color: NSColor?
    let url: URL?
    let filePath: String?
    
    static let empty = ContentDetectionResult(trimmedText: "", color: nil, url: nil, filePath: nil)
    
    var isURL: Bool { url != nil }
    var isFilePath: Bool { filePath != nil }
    
    func colorString(format: ColorFormat) -> String? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
            let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
            let delta = maxC - minC
            let l = (maxC + minC) / 2
            guard delta > 0.001 else { return "hsl(0\u{00B0}, 0%, \(Int(round(l * 100)))%)" }
            let s = delta / (1 - abs(2 * l - 1))
            var h: Double
            if maxC == rf { h = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxC == gf { h = 60 * (((bf - rf) / delta) + 2) }
            else { h = 60 * (((rf - gf) / delta) + 4) }
            if h < 0 { h += 360 }
            return "hsl(\(Int(round(h)))\u{00B0}, \(Int(round(s * 100)))%, \(Int(round(l * 100)))%)"
        }
    }
}

private final class ContentDetectionBox: NSObject {
    let result: ContentDetectionResult
    
    init(_ result: ContentDetectionResult) {
        self.result = result
    }
}

private final class TimestampedBool: NSObject {
    let value: Bool
    let timestamp: Date
    
    init(_ value: Bool) {
        self.value = value
        self.timestamp = Date()
    }
    
    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}
struct ContentDetector {
    private static let rgbRegex = try? NSRegularExpression(
        pattern: #"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)"#,
        options: .caseInsensitive
    )
    
    static let filePathTTL: TimeInterval = 60
    
    private static let filePathCache: NSCache<NSString, TimestampedBool> = {
        let cache = NSCache<NSString, TimestampedBool>()
        cache.countLimit = 512
        return cache
    }()
    
    private static let analysisCache: NSCache<NSString, ContentDetectionBox> = {
        let cache = NSCache<NSString, ContentDetectionBox>()
        cache.countLimit = 1024
        return cache
    }()
    
    static func analyze(_ text: String) -> ContentDetectionResult {
        let prefix = text.prefix(2_049)
        guard prefix.count <= 2_048 else { return .empty }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        
        let cacheKey = trimmed as NSString
        if let cached = analysisCache.object(forKey: cacheKey) {
            return cached.result
        }
        
        let result = ContentDetectionResult(
            trimmedText: trimmed,
            color: detectColor(in: trimmed),
            url: detectURL(in: trimmed),
            filePath: detectFilePath(in: trimmed)
        )
        analysisCache.setObject(ContentDetectionBox(result), forKey: cacheKey)
        return result
    }
    
    static func detectColor(_ text: String) -> NSColor? {
        analyze(text).color
    }
    
    static func isURL(_ text: String) -> Bool {
        analyze(text).isURL
    }
    
    static func isFilePath(_ text: String) -> Bool {
        analyze(text).isFilePath
    }
    
    private static func detectColor(in trimmed: String) -> NSColor? {
        // HEX: #RGB, #RRGGBB, #RRGGBBAA
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            if let color = NSColor(hexString: hex) { return color }
        }
        // rgb(r, g, b) or rgba(r, g, b, a)
        if let regex = rgbRegex,
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let r = min(max(Int((trimmed as NSString).substring(with: match.range(at: 1))) ?? 0, 0), 255)
            let g = min(max(Int((trimmed as NSString).substring(with: match.range(at: 2))) ?? 0, 0), 255)
            let b = min(max(Int((trimmed as NSString).substring(with: match.range(at: 3))) ?? 0, 0), 255)
            let alpha = match.range(at: 4).location != NSNotFound
                ? Double((trimmed as NSString).substring(with: match.range(at: 4))) ?? 1.0
                : 1.0
            let a = min(max(alpha, 0.0), 1.0)
            return NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: CGFloat(a))
        }
        return nil
    }
    
    private static func detectURL(in trimmed: String) -> URL? {
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else {
            return nil
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }
        return components.url ?? URL(string: trimmed)
    }
    
    private static func detectFilePath(in trimmed: String) -> String? {
        var candidatePath: String?
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            candidatePath = (trimmed as NSString).expandingTildeInPath
        } else if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            candidatePath = url.path
        }
        
        guard let expanded = candidatePath else { return nil }
        return cachedFileExists(at: expanded) ? expanded : nil
    }
    
    private static func cachedFileExists(at path: String) -> Bool {
        let key = path as NSString
        if let cached = filePathCache.object(forKey: key), !cached.isExpired(ttl: filePathTTL) {
            return cached.value
        }
        let exists = FileManager.default.fileExists(atPath: path)
        filePathCache.setObject(TimestampedBool(exists), forKey: key)
        return exists
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgbValue) else { return nil }
        if hex.count == 6 {
            self.init(red: CGFloat((rgbValue >> 16) & 0xFF) / 255,
                      green: CGFloat((rgbValue >> 8) & 0xFF) / 255,
                      blue: CGFloat(rgbValue & 0xFF) / 255, alpha: 1)
        } else {
            self.init(red: CGFloat((rgbValue >> 24) & 0xFF) / 255,
                      green: CGFloat((rgbValue >> 16) & 0xFF) / 255,
                      blue: CGFloat((rgbValue >> 8) & 0xFF) / 255,
                      alpha: CGFloat(rgbValue & 0xFF) / 255)
        }
    }
}
