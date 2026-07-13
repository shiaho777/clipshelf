import Foundation

enum ClipboardContentCodec {
    static func encodeFilePaths(_ paths: [String]) -> String {
        if let data = try? JSONEncoder().encode(paths), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return paths.joined(separator: "\n")
    }
}
