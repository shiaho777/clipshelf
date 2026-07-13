import Foundation
import AppKit

// MARK: - Protocol & Payload

struct PastePayload {
    let string: String?
    let rtf: Data?
    let html: Data?
}

protocol PasteAdapter {
    var targetBundleIDs: Set<String> { get }
    /// Human-readable name shown in the app-aware paste status bar badge.
    var adapterName: String { get }
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload
}

// MARK: - Shared Utilities

enum PasteAdapterUtils {
    // MARK: Code detection

    /// Returns true only when the text is very likely source code.
    /// Explicitly rejects JSON/plist structures to avoid false positives.
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Single-line content is never auto-wrapped as a code block.
        guard lines.count >= 2 else { return false }

        // Bail out early for JSON / plist — these are data, not code.
        if isLikelyJSON(text) { return false }

        let lower = text.lowercased()

        // Strong signals: any one match is sufficient.
        let strong = [
            "func ", "def ", "export ", "const ",
            "return ", "if (", "for (", "while (",
            "#!/", "#include", "#import",
            "public class", "private class", "protected class",
            "public func", "private func", "async def",
            "fn ", "void ", "int main",
            "console.log", "system.out", "std::",
            "lambda ", "yield ", "try:", "except:",
            "let mut ", "impl ", "#pragma"
        ]
        if strong.contains(where: { lower.contains($0) }) { return true }

        // Weak signals: require at least 3 co-occurring indicators.
        let weak = ["->", "=>", "//", "/*", "*/", "};", ":: "]
        let weakCount = weak.filter { text.contains($0) }.count
        return weakCount >= 3
    }

    /// Returns true when the text is parseable JSON or looks like a JSON structure.
    static func isLikelyJSON(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (t.hasPrefix("{") && t.hasSuffix("}")) ||
              (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil
    }

    /// Returns true when a single-line string looks like a code expression.
    /// Used by MessagingAdapter to wrap brief code snippets in backticks.
    /// Deliberately excludes `let ` and `var ` to avoid false-positives on
    /// English prose like "let me know" or "var $100 increase".
    static func looksLikeSingleLineCode(_ text: String) -> Bool {
        guard !text.contains("\n") else { return false }
        if isLikelyJSON(text) { return false }
        let lower = text.lowercased()
        let strong = [
            "func ", "def ", "const ", "return ", "if (", "for (", "while (",
            "console.log(", "print(", "=>", "std::", "self.", "this.",
            "#!", "#include", "->("
        ]
        return strong.contains(where: { lower.contains($0) })
    }

    // MARK: Shell helpers

    /// Does the text contain shell-special characters that need escaping?
    static func needsShellEscaping(_ text: String) -> Bool {
        let dangerChars: Set<Character> = ["$", "`", "\\", "!", "\"", "(", ")", "{", "}", "|", ";", "&", "<", ">"]
        return text.contains(where: { dangerChars.contains($0) })
    }

    /// Wrap text in single quotes, escaping existing single quotes for safe shell paste.
    static func shellEscape(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

// MARK: - Markdown Adapter

/// Targets: VSCode, Obsidian, Typora, iA Writer
/// - URLs → `[domain](url)`
/// - Multi-line code → wrapped in ```
struct MarkdownAdapter: PasteAdapter {
    let adapterName = "Markdown"
    let targetBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "md.obsidian",
        "abnerworks.Typora",
        "pro.writer.mac"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        guard type != .image else { return PastePayload(string: content, rtf: nil, html: nil) }
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // URL → Markdown link
        if let url = URL(string: trimmed), let host = url.host, url.scheme?.hasPrefix("http") == true {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return PastePayload(string: "[\(domain)](\(trimmed))", rtf: nil, html: nil)
        }
        
        // Multi-line content that looks like code → wrap in fences
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3, PasteAdapterUtils.looksLikeCode(trimmed) {
            return PastePayload(string: "```\n\(trimmed)\n```", rtf: nil, html: nil)
        }
        
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Terminal Adapter

/// Targets: Terminal.app, iTerm2, Warp, Alacritty, kitty, Hyper, Rio, WezTerm
/// Rules:
///  - Multi-line content: never escape (could be a script intended for paste as-is)
///  - Long content (>200 chars): never escape
///  - Starts with "$ " or "% ": strip the prompt marker, pass through
///  - Content that looks like code: pass through without escaping
///  - Short single-line with shell-special chars: wrap in single quotes
struct TerminalAdapter: PasteAdapter {
    let adapterName = "Terminal"
    let targetBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.raphaelamorim.rio",
        "com.github.wez.wezterm"
    ]

    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        guard type == .text else { return PastePayload(string: content, rtf: nil, html: nil) }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Multi-line: preserve as-is (user is pasting a script or block of text)
        guard !trimmed.contains("\n") else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        // Long content: not a shell command, skip escaping
        guard trimmed.count <= 200 else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        // Strip common shell prompt prefixes
        if trimmed.hasPrefix("$ ") {
            return PastePayload(string: String(trimmed.dropFirst(2)), rtf: nil, html: nil)
        }
        if trimmed.hasPrefix("% ") {
            return PastePayload(string: String(trimmed.dropFirst(2)), rtf: nil, html: nil)
        }

        // No dangerous characters — pass through unchanged
        guard PasteAdapterUtils.needsShellEscaping(trimmed) else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        // Looks like a code expression, not a shell argument — don't quote it
        if PasteAdapterUtils.looksLikeCode(trimmed) {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        return PastePayload(string: PasteAdapterUtils.shellEscape(trimmed), rtf: nil, html: nil)
    }
}

// MARK: - Xcode Adapter

/// Targets: Xcode
/// - Strip rich text formatting — Xcode works best with plain text paste.
struct XcodeAdapter: PasteAdapter {
    let adapterName = "Xcode"
    let targetBundleIDs: Set<String> = [
        "com.apple.dt.Xcode"
    ]

    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        // Force plain text to avoid Xcode interpreting RTF attributes
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Email Adapter

/// Targets: Mail.app, Spark, Airmail, Mimestream
/// - URLs → clickable HTML link
struct EmailAdapter: PasteAdapter {
    let adapterName = "Email"
    let targetBundleIDs: Set<String> = [
        "com.apple.mail",
        "com.readdle.smartemail",
        "it.bloop.airmail2",
        "com.mimestream.Mimestream"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        guard type != .image else { return PastePayload(string: content, rtf: nil, html: nil) }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, url.scheme?.hasPrefix("http") == true {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let html = "<a href=\"\(trimmed)\">\(domain)</a>"
            return PastePayload(string: trimmed, rtf: nil, html: html.data(using: .utf8))
        }
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Messaging Adapter

/// Targets: Discord, Telegram, WhatsApp, Signal, Messages
/// - Multi-line code → wrapped in ```
/// - Single-line code → wrapped in `
struct MessagingAdapter: PasteAdapter {
    let adapterName = "Messaging"
    let targetBundleIDs: Set<String> = [
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "org.whispersystems.signal-desktop",
        "com.apple.MobileSMS",
        "com.tinyspeck.slackmacgap"  // Slack also fits messaging pattern
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        guard type == .text else { return PastePayload(string: content, rtf: nil, html: nil) }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 2, PasteAdapterUtils.looksLikeCode(trimmed) {
            return PastePayload(string: "```\n\(trimmed)\n```", rtf: nil, html: nil)
        }
        if PasteAdapterUtils.looksLikeSingleLineCode(trimmed) {
            return PastePayload(string: "`\(trimmed)`", rtf: nil, html: nil)
        }
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Note-Taking Adapter

/// Targets: Bear, Craft, Ulysses, Apple Notes, Notion, Joplin
/// - URLs → `[domain](url)`
/// - Multi-line code → wrapped in ```
struct NoteAdapter: PasteAdapter {
    let adapterName = "Notes"
    let targetBundleIDs: Set<String> = [
        "net.shinyfrog.bear",
        "com.lukilabs.lukiapp",
        "com.ulyssesapp.mac",
        "com.apple.Notes",
        "notion.id",
        "net.cozic.joplin-desktop"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        guard type != .image else { return PastePayload(string: content, rtf: nil, html: nil) }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, url.scheme?.hasPrefix("http") == true {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return PastePayload(string: "[\(domain)](\(trimmed))", rtf: nil, html: nil)
        }
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3, PasteAdapterUtils.looksLikeCode(trimmed) {
            return PastePayload(string: "```\n\(trimmed)\n```", rtf: nil, html: nil)
        }
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - iWork Adapter

/// Targets: Pages, Numbers, Keynote
/// - Always strip to plain text for clean paste.
struct IWorkAdapter: PasteAdapter {
    let adapterName = "iWork"
    let targetBundleIDs: Set<String> = [
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        // Force plain text — iWork apps handle their own formatting
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Plain Text Editor Adapter

/// Targets: TextEdit, BBEdit, Sublime Text, Nova, CotEditor, Vim (MacVim)
/// - Strip RTF to ensure clean plain text paste.
struct PlainTextEditorAdapter: PasteAdapter {
    let adapterName = "Plain Text"
    let targetBundleIDs: Set<String> = [
        "com.apple.TextEdit",
        "com.barebones.bbedit",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.Nova",
        "com.coteditor.CotEditor",
        "org.vim.MacVim",
        "com.github.atom",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.CLion",
        "com.jetbrains.goland",
        "com.jetbrains.rider"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

// MARK: - Paste Adapter Manager

final class PasteAdapterManager {
    static let shared = PasteAdapterManager()

    /// Bundle-ID → adapter mapping built once at init for O(1) lookup.
    private let adapterMap: [String: any PasteAdapter]

    init() {
        let allAdapters: [any PasteAdapter] = [
            MarkdownAdapter(),
            TerminalAdapter(),       // includes Hyper, Rio, WezTerm
            MessagingAdapter(),      // Discord, Telegram, WhatsApp, Signal, Messages, Slack
            NoteAdapter(),           // Bear, Craft, Ulysses, Notes, Notion, Joplin
            EmailAdapter(),
            XcodeAdapter(),
            IWorkAdapter(),
            PlainTextEditorAdapter()
        ]
        var map: [String: any PasteAdapter] = [:]
        for adapter in allAdapters {
            for bundleID in adapter.targetBundleIDs {
                map[bundleID] = adapter
            }
        }
        adapterMap = map
    }

    /// Returns the adapted payload if a matching adapter is found, nil otherwise.
    func adaptedPayload(for bundleID: String, content: String, type: ClipboardItem.ItemType) -> PastePayload? {
        guard let adapter = adapterMap[bundleID] else { return nil }
        let payload = adapter.adapt(content, type: type)
        // Only return if the adapter actually changed the content
        if payload.string == content && payload.rtf == nil && payload.html == nil {
            return nil
        }
        return payload
    }

    /// Returns the display name of the adapter that would apply to the given bundle ID, or nil.
    func adapterName(for bundleID: String) -> String? {
        adapterMap[bundleID]?.adapterName
    }
}
