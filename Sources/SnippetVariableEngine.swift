import Foundation

/// Expands snippet template variables at insertion time.
///
/// Supported variables:
/// - `{{date:format}}`  — current date using `DateFormatter` format string
/// - `{{date}}`          — current date, locale short style
/// - `{{time:format}}`  — current time using `DateFormatter` format string
/// - `{{time}}`          — current time, locale short style
/// - `{{datetime}}`     — current date + time in ISO 8601
/// - `{{clipboard}}`   — current clipboard plain-text content
/// - `{{random:N}}`    — N-character alphanumeric random string
/// - `{{cursor}}`      — cursor placement marker; removed from output; `cursorBackCount`
///                       gives the number of Left-arrow key presses needed to land there
struct SnippetVariableEngine {

    /// Expand all supported `{{variable}}` patterns in `template`.
    ///
    /// - Parameters:
    ///   - template:       The raw snippet content, potentially containing `{{…}}` tokens.
    ///   - clipboardText:  The plain-text content already on the clipboard before expansion.
    ///   - now:            Reference timestamp; defaults to `Date()`.
    /// - Returns: `(expanded, cursorBackCount)` where `cursorBackCount` is the number of
    ///   Left-arrow presses needed to position the cursor at the `{{cursor}}` marker.
    static func expand(
        template: String,
        clipboardText: String,
        now: Date = Date()
    ) -> (expanded: String, cursorBackCount: Int) {
        var result = template

        // {{date:format}} — e.g. {{date:yyyy-MM-dd}}
        result = result.replacingMatches(of: #"\{\{date:([^}]+)\}\}"#) { _, groups in
            let df = DateFormatter()
            df.dateFormat = groups.first ?? "yyyy-MM-dd"
            return df.string(from: now)
        }
        // {{date}} (no format — locale short)
        if result.contains("{{date}}") {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .none
            result = result.replacingOccurrences(of: "{{date}}", with: df.string(from: now))
        }

        // {{time:format}} — e.g. {{time:HH:mm:ss}}
        result = result.replacingMatches(of: #"\{\{time:([^}]+)\}\}"#) { _, groups in
            let df = DateFormatter()
            df.dateFormat = groups.first ?? "HH:mm"
            return df.string(from: now)
        }
        // {{time}} (no format — locale short)
        if result.contains("{{time}}") {
            let df = DateFormatter()
            df.dateStyle = .none
            df.timeStyle = .short
            result = result.replacingOccurrences(of: "{{time}}", with: df.string(from: now))
        }

        // {{datetime}} — ISO 8601
        if result.contains("{{datetime}}") {
            result = result.replacingOccurrences(
                of: "{{datetime}}",
                with: ISO8601DateFormatter().string(from: now)
            )
        }

        // {{clipboard}} — current clipboard text
        if result.contains("{{clipboard}}") {
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardText)
        }

        // {{random:N}} — N-character alphanumeric
        result = result.replacingMatches(of: #"\{\{random:(\d+)\}\}"#) { _, groups in
            let n = max(1, Int(groups.first ?? "8") ?? 8)
            let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            return String((0..<n).map { _ in charset.randomElement()! })
        }

        // {{cursor}} — track position then remove marker
        var cursorBackCount = 0
        if let cursorRange = result.range(of: "{{cursor}}") {
            cursorBackCount = result.distance(from: cursorRange.upperBound, to: result.endIndex)
            result = result.replacingCharacters(in: cursorRange, with: "")
        }

        return (result, cursorBackCount)
    }
}

// MARK: - Regex replace helper

private extension String {
    /// Replace every match of `pattern` by invoking `transform(matchString, captureGroups)`.
    func replacingMatches(
        of pattern: String,
        using transform: (_ match: String, _ groups: [String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let nsString = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return self }

        var output = ""
        var lastEnd = startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: self) else { continue }
            output += self[lastEnd..<matchRange.lowerBound]

            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                if let gr = Range(match.range(at: i), in: self) {
                    groups.append(String(self[gr]))
                } else {
                    groups.append("")
                }
            }
            output += transform(String(self[matchRange]), groups)
            lastEnd = matchRange.upperBound
        }
        output += self[lastEnd...]
        return output
    }
}
