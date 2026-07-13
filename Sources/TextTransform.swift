import Foundation
import CryptoKit

enum TextTransform: String, CaseIterable {
    case uppercase
    case lowercase
    case capitalize
    case trimWhitespace
    case removeBlankLines
    case urlEncode
    case urlDecode
    case jsonFormat
    case base64Encode
    case base64Decode
    // Developer tools (Phase 3)
    case jsonEscape
    case swiftStringLiteral
    case jsStringLiteral
    case hexEncode
    case hexDecode
    case htmlEntitiesEncode
    case htmlEntitiesDecode
    case sha256Hash
    case xmlFormat

    var localizationKey: String { "transform.\(rawValue)" }

    func apply(_ input: String) -> String? {
        switch self {
        case .uppercase:
            return input.uppercased()
        case .lowercase:
            return input.lowercased()
        case .capitalize:
            return input.capitalized
        case .trimWhitespace:
            let lines = input.components(separatedBy: .newlines)
            return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeBlankLines:
            return input.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode:
            return input.removingPercentEncoding
        case .jsonFormat:
            return Self.formatJSON(input)
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            return decoded
        case .jsonEscape:
            return Self.jsonEscapeString(input)
        case .swiftStringLiteral:
            let esc = input
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\0", with: "\\0")
            return "\"\(esc)\""
        case .jsStringLiteral:
            let esc = input
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\0", with: "\\0")
            return "\"\(esc)\""
        case .hexEncode:
            return Data(input.utf8).map { String(format: "%02x", $0) }.joined()
        case .hexDecode:
            return Self.hexDecodeString(input)
        case .htmlEntitiesEncode:
            return input
                .replacingOccurrences(of: "&",  with: "&amp;")
                .replacingOccurrences(of: "<",  with: "&lt;")
                .replacingOccurrences(of: ">",  with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'",  with: "&#39;")
        case .htmlEntitiesDecode:
            return Self.htmlDecode(input)
        case .sha256Hash:
            let digest = SHA256.hash(data: Data(input.utf8))
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        case .xmlFormat:
            return Self.formatXML(input)
        }
    }

    // MARK: - Private helpers

    private static func formatJSON(_ input: String) -> String? {
        guard let data = input.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func jsonEscapeString(_ input: String) -> String? {
        // Wrap in array so JSONSerialization accepts a String value
        guard let data = try? JSONSerialization.data(withJSONObject: [input]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 4 else { return nil }
        // Strip surrounding [" ... "]
        let start = json.index(json.startIndex, offsetBy: 2)
        let end   = json.index(json.endIndex,   offsetBy: -2)
        guard start <= end else { return nil }
        return String(json[start..<end])
    }

    private static func hexDecodeString(_ input: String) -> String? {
        let cleaned = input.replacingOccurrences(of: " ", with: "").lowercased()
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func htmlDecode(_ input: String) -> String {
        var result = input
        let namedEntities: [(String, String)] = [
            ("&amp;",  "&"),  ("&lt;",   "<"),  ("&gt;",   ">"),
            ("&quot;", "\""), ("&#39;",  "'"),  ("&apos;", "'"),
            ("&nbsp;", " "),  ("&copy;", "©"),  ("&reg;",  "®"),
            ("&trade;","™"),  ("&mdash;","—"),  ("&ndash;","–"),
        ]
        for (entity, char) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#NNN; and &#xHHH;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);|&#x([0-9a-fA-F]+);") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                var codePoint: UInt32?
                if let r = Range(match.range(at: 1), in: result), !result[r].isEmpty {
                    codePoint = UInt32(result[r])
                } else if let r = Range(match.range(at: 2), in: result), !result[r].isEmpty {
                    codePoint = UInt32(result[r], radix: 16)
                }
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        return result
    }

    private static func formatXML(_ input: String) -> String? {
        guard let data = input.data(using: .utf8) else { return nil }
        do {
            let doc = try XMLDocument(data: data, options: .nodePrettyPrint)
            return doc.xmlString(options: .nodePrettyPrint)
        } catch {
            return nil
        }
    }
}
