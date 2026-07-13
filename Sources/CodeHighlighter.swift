import AppKit

/// Lightweight, dependency-free syntax highlighter for the clipboard preview.
///
/// Uses a token-based approach with language-agnostic keyword sets covering
/// 30+ languages well enough for at-a-glance code identification in a preview panel.
/// For full-fidelity highlighting the user should paste into their editor.
enum CodeHighlighter {

    // MARK: - Language Detection

    /// A best-effort guess at the source language of `text`.
    /// Returns `nil` when the text does not look like code.
    static func detectLanguage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Shebang → shell / script
        if trimmed.hasPrefix("#!") {
            if trimmed.contains("python") { return "python" }
            if trimmed.contains("ruby") { return "ruby" }
            if trimmed.contains("node") { return "javascript" }
            return "shell"
        }

        // XML / HTML
        if trimmed.hasPrefix("<?xml") { return "xml" }
        if trimmed.hasPrefix("<!DOCTYPE html") || (trimmed.hasPrefix("<html") && trimmed.contains("</html>")) { return "html" }

        // Swift
        if trimmed.contains("import Foundation") || trimmed.contains("import SwiftUI") || trimmed.contains("import UIKit") { return "swift" }
        if containsAny(trimmed, ["func ", "let ", "var ", "guard let", "import "]) && containsAny(trimmed, ["{", "}", "->"]) {
            return "swift"
        }

        // Rust
        if containsAny(trimmed, ["fn ", "impl ", "let mut ", "use std::", "pub fn "]) { return "rust" }

        // Go
        if containsAny(trimmed, ["package main", "func main()", "import ("]) { return "go" }

        // Python — require strong signals: `def ` followed by an identifier, or
        // `import`/`from` combined with another Python-specific signal.
        // Using regex to avoid false positives like "def initely" in English prose.
        if let regex = try? NSRegularExpression(pattern: #"\bdef\s+\w+\s*\("#) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, range: range) != nil { return "python" }
        }
        if containsAny(trimmed, ["print(", "self.", "__init__", "elif ", "lambda "]) {
            return "python"
        }
        if containsAny(trimmed, ["import ", "from "]) && containsAny(trimmed, ["print(", "self.", "__init__", "#!/usr/bin/env python"]) {
            return "python"
        }

        // JavaScript / TypeScript
        if containsAny(trimmed, ["const ", "export ", "require(", "console.log", "function ", "=>"]) {
            if containsAny(trimmed, [": string", ": number", ": boolean", "interface ", "type "]) { return "typescript" }
            return "javascript"
        }

        // Java / Kotlin / C#
        if containsAny(trimmed, ["public class", "public static void main", "System.out"]) { return "java" }
        if containsAny(trimmed, ["fun ", "val ", "when ("]) { return "kotlin" }
        if containsAny(trimmed, ["using System", "namespace ", "public void "]) { return "csharp" }

        // C / C++
        if containsAny(trimmed, ["#include", "#import", "int main(", "std::"]) { return "cpp" }

        // Shell — require shebang or 2+ signals to avoid false positives.
        if trimmed.hasPrefix("#!/bin/") { return "shell" }
        let shellSignals = ["echo ", "export ", "grep ", "sed ", "awk ", "$(", "${", "|| ", "&& "]
        let shellCount = shellSignals.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        if shellCount >= 2 { return "shell" }

        // SQL
        let lower = trimmed.lowercased()
        if containsAny(lower, ["select ", "from ", "where ", "insert into ", "create table "]) { return "sql" }

        // CSS
        if trimmed.contains("{") && trimmed.contains("}") && trimmed.contains(":") && trimmed.contains(";") && !trimmed.contains("//") {
            if containsAny(lower, ["color:", "background", "margin:", "padding:", "font-size:"]) { return "css" }
        }

        // JSON
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [])) != nil {
            return "json"
        }

        // YAML
        if trimmed.contains(":\n") && !trimmed.contains("{") && !trimmed.contains("}") {
            if containsAny(lower, ["version:", "services:", "name:", "description:"]) { return "yaml" }
        }

        return nil
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    // MARK: - Theme

    struct Theme {
        let plain: NSColor
        let keyword: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let type: NSColor
        let attribute: NSColor

        static let `default` = Theme(
            plain: NSColor.labelColor,
            keyword: NSColor(red: 0.69, green: 0.18, blue: 0.38, alpha: 1),   // pinkish red
            string: NSColor(red: 0.20, green: 0.55, blue: 0.30, alpha: 1),    // green
            number: NSColor(red: 0.78, green: 0.45, blue: 0.10, alpha: 1),    // orange
            comment: NSColor.secondaryLabelColor,
            type: NSColor(red: 0.30, green: 0.40, blue: 0.75, alpha: 1),      // blue-purple
            attribute: NSColor(red: 0.50, green: 0.35, blue: 0.65, alpha: 1)  // purple
        )
    }

    // MARK: - Highlight

    /// Returns a syntax-highlighted `NSAttributedString` for the given code text.
    /// If `text` doesn't look like code, returns a plain attributed string.
    static func highlighted(_ text: String, font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular), theme: Theme = .default) -> NSAttributedString {
        guard let language = detectLanguage(text) else {
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: theme.plain
            ])
        }

        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: theme.plain
        ])

        applyComments(result, text: text, language: language, theme: theme)
        applyStrings(result, text: text, theme: theme)
        applyNumbers(result, text: text, theme: theme)
        applyKeywords(result, text: text, language: language, theme: theme)

        return result
    }

    // MARK: - Pattern Application

    private static func applyComments(_ attr: NSMutableAttributedString, text: String, language: String, theme: Theme) {
        // Line comments — only apply the patterns relevant to the detected language.
        let slashCommentLanguages: Set<String> = [
            "swift", "javascript", "typescript", "java", "kotlin", "csharp",
            "cpp", "c", "rust", "go", "css", "php"
        ]
        let hashCommentLanguages: Set<String> = ["shell", "python", "yaml", "ruby", "perl"]
        let dashCommentLanguages: Set<String> = ["sql", "lua"]

        var patterns: [String] = []
        if slashCommentLanguages.contains(language) {
            // Match // but NOT :// (URLs)
            patterns.append(#"(?<!:)//[^\n]*"#)
        }
        if hashCommentLanguages.contains(language) {
            patterns.append(#"#[^\n]*"#)
        }
        if dashCommentLanguages.contains(language) {
            patterns.append(#"--[^\n]*"#)
        }
        guard !patterns.isEmpty else { return }
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                // For # comments, avoid coloring hex colors like #FF0000
                    let matched = (text as NSString).substring(with: match.range)
                    if matched.hasPrefix("#") && matched.count <= 9 {
                        let hex = matched.dropFirst()
                        if hex.allSatisfy({ $0.isHexDigit }) { return }
                    }
                attr.addAttribute(.foregroundColor, value: theme.comment, range: match.range)
            }
        }

        // Block comments: /* ... */
        if let regex = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                attr.addAttribute(.foregroundColor, value: theme.comment, range: match.range)
            }
        }
    }

    private static func applyStrings(_ attr: NSMutableAttributedString, text: String, theme: Theme) {
        // Double-quoted and single-quoted strings
        let patterns = [
            #""(?:[^"\\]|\\.)*""#,
            #"'(?:[^'\\]|\\.)*'"#,
            #"`(?:[^`\\]|\\.)*`"#,  // template literals / backtick strings
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                attr.addAttribute(.foregroundColor, value: theme.string, range: match.range)
            }
        }
    }

    private static func applyNumbers(_ attr: NSMutableAttributedString, text: String, theme: Theme) {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*([eE][+-]?\d+)?\b"#) else { return }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            attr.addAttribute(.foregroundColor, value: theme.number, range: match.range)
        }
    }

    private static let keywordSets: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "for", "in", "while", "switch", "case", "default", "break", "continue", "return", "struct", "class", "enum", "protocol", "extension", "import", "public", "private", "internal", "fileprivate", "static", "self", "super", "nil", "true", "false", "throws", "rethrows", "try", "catch", "throw", "async", "await", "actor", "some", "any", "where", "as", "is", "init", "deinit", "defer", "inout", "mutating", "nonmutating", "override", "weak", "unowned", "lazy", "optional", "required", "convenience"],
        "javascript": ["const", "let", "var", "function", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "class", "extends", "super", "new", "this", "typeof", "instanceof", "in", "of", "import", "export", "from", "default", "async", "await", "try", "catch", "finally", "throw", "delete", "void", "yield", "true", "false", "null", "undefined", "static", "get", "set"],
        "typescript": ["const", "let", "var", "function", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "class", "extends", "super", "new", "this", "typeof", "instanceof", "in", "of", "import", "export", "from", "default", "async", "await", "try", "catch", "finally", "throw", "delete", "void", "yield", "true", "false", "null", "undefined", "static", "get", "set", "type", "interface", "enum", "namespace", "declare", "abstract", "readonly", "keyof", "infer", "is", "as", "satisfies"],
        "python": ["def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "break", "continue", "return", "yield", "try", "except", "finally", "raise", "with", "lambda", "pass", "del", "global", "nonlocal", "assert", "in", "is", "not", "and", "or", "True", "False", "None", "self", "async", "await", "print"],
        "rust": ["fn", "let", "mut", "if", "else", "for", "while", "loop", "match", "return", "break", "continue", "struct", "enum", "trait", "impl", "use", "mod", "pub", "priv", "crate", "self", "super", "as", "in", "ref", "move", "static", "const", "unsafe", "async", "await", "dyn", "where", "type", "true", "false", "Some", "None", "Ok", "Err"],
        "go": ["func", "var", "const", "type", "struct", "interface", "package", "import", "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "return", "go", "defer", "select", "chan", "map", "make", "new", "len", "cap", "append", "copy", "delete", "panic", "recover", "true", "false", "nil"],
        "java": ["public", "private", "protected", "class", "interface", "extends", "implements", "static", "final", "void", "int", "long", "double", "float", "boolean", "char", "byte", "short", "String", "if", "else", "for", "while", "switch", "case", "break", "continue", "return", "new", "this", "super", "try", "catch", "finally", "throw", "throws", "import", "package", "true", "false", "null", "instanceof", "synchronized", "abstract", "enum"],
        "kotlin": ["fun", "val", "var", "class", "object", "interface", "enum", "sealed", "data", "if", "else", "for", "while", "when", "is", "in", "as", "return", "break", "continue", "import", "package", "override", "open", "abstract", "final", "private", "public", "internal", "protected", "companion", "init", "this", "super", "null", "true", "false", "try", "catch", "finally", "throw", "suspend", "inline", "reified", "by", "lateinit"],
        "csharp": ["using", "namespace", "class", "interface", "struct", "enum", "public", "private", "protected", "internal", "static", "void", "int", "string", "bool", "double", "float", "var", "new", "return", "if", "else", "for", "foreach", "while", "switch", "case", "break", "continue", "try", "catch", "finally", "throw", "this", "base", "null", "true", "false", "override", "virtual", "abstract", "sealed", "async", "await", "get", "set", "readonly"],
        "cpp": ["int", "char", "double", "float", "void", "bool", "long", "short", "unsigned", "signed", "const", "static", "struct", "class", "public", "private", "protected", "if", "else", "for", "while", "switch", "case", "break", "continue", "return", "new", "delete", "this", "nullptr", "true", "false", "include", "import", "using", "namespace", "template", "typename", "auto", "virtual", "override", "std", "vector", "string", "map"],
        "c": ["int", "char", "double", "float", "void", "bool", "long", "short", "unsigned", "signed", "const", "static", "struct", "typedef", "if", "else", "for", "while", "switch", "case", "break", "continue", "return", "sizeof", "NULL", "true", "false", "include", "define", "ifdef", "ifndef", "endif"],
        "shell": ["echo", "cd", "ls", "mkdir", "rm", "cp", "mv", "cat", "grep", "sed", "awk", "find", "export", "source", "alias", "if", "then", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "exit", "local", "readonly", "declare", "set", "unset", "trap", "test"],
        "sql": ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "DISTINCT", "UNION", "ALL", "AND", "OR", "NOT", "NULL", "IS", "IN", "LIKE", "BETWEEN", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "COUNT", "SUM", "AVG", "MIN", "MAX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE", "CONSTRAINT"],
        "ruby": ["def", "end", "if", "elsif", "else", "unless", "while", "until", "for", "do", "break", "next", "redo", "retry", "return", "yield", "begin", "rescue", "ensure", "raise", "throw", "catch", "module", "class", "require", "require_relative", "include", "extend", "attr_accessor", "attr_reader", "attr_writer", "public", "private", "protected", "self", "super", "nil", "true", "false", "puts", "print", "lambda", "proc"],
        "php": ["function", "class", "interface", "trait", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "const", "var", "if", "elseif", "else", "for", "foreach", "while", "do", "switch", "case", "break", "continue", "return", "new", "clone", "this", "self", "parent", "null", "true", "false", "use", "namespace", "try", "catch", "finally", "throw", "isset", "unset", "echo", "print", "require", "include"],
    ]

    private static func applyKeywords(_ attr: NSMutableAttributedString, text: String, language: String, theme: Theme) {
        let lowerLang = language == "typescript" ? "typescript" : language
        guard let keywords = keywordSets[lowerLang] ?? keywordSets[language] else { return }

        let isCaseInsensitive = (language == "sql")
        let options: NSRegularExpression.Options = isCaseInsensitive ? [.caseInsensitive] : []

        for keyword in keywords {
            // Match whole word only
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                attr.addAttribute(.foregroundColor, value: theme.keyword, range: match.range)
            }
        }

        // Type-like identifiers: CapitalizedWords
        if let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z0-9]*\b"#) {
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                // Don't override already-colored strings / comments
                let existing = attr.attribute(.foregroundColor, at: match.range.location, effectiveRange: nil) as? NSColor
                if existing == theme.string || existing == theme.comment || existing == theme.number { return }
                attr.addAttribute(.foregroundColor, value: theme.type, range: match.range)
            }
        }
    }

    // MARK: - UITextView wrapper for SwiftUI

    /// SwiftUI wrapper that renders syntax-highlighted code in a scrollable text view.
    static func makeScrollView(for text: String) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)

        let highlighted = highlighted(text)
        textView.textStorage?.setAttributedString(highlighted)

        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        scrollView.documentView = textView
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.size = NSSize(width: scrollView.contentSize.width - 12, height: .greatestFiniteMagnitude)
        }
        return scrollView
    }
}
