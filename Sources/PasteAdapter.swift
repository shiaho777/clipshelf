import Foundation
import AppKit

struct PastePayload {
    let string: String?
    let rtf: Data?
    let html: Data?
}

protocol PasteAdapter {
    var targetBundleIDs: Set<String> { get }
    var adapterName: String { get }
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload
}

enum PasteAdapterUtils {
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return false }

        if isLikelyJSON(text) { return false }

        let lower = text.lowercased()

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

        let weak = ["->", "=>", "//", "/*", "*/", "};", ":: "]
        let weakCount = weak.filter { text.contains($0) }.count
        return weakCount >= 3
    }

    static func isLikelyJSON(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (t.hasPrefix("{") && t.hasSuffix("}")) ||
              (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil
    }

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

    static func needsShellEscaping(_ text: String) -> Bool {
        let dangerChars: Set<Character> = ["$", "`", "\\", "!", "\"", "(", ")", "{", "}", "|", ";", "&", "<", ">"]
        return text.contains(where: { dangerChars.contains($0) })
    }

    static func shellEscape(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

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

        guard !trimmed.contains("\n") else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        guard trimmed.count <= 200 else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        if trimmed.hasPrefix("$ ") {
            return PastePayload(string: String(trimmed.dropFirst(2)), rtf: nil, html: nil)
        }
        if trimmed.hasPrefix("% ") {
            return PastePayload(string: String(trimmed.dropFirst(2)), rtf: nil, html: nil)
        }

        guard PasteAdapterUtils.needsShellEscaping(trimmed) else {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        if PasteAdapterUtils.looksLikeCode(trimmed) {
            return PastePayload(string: trimmed, rtf: nil, html: nil)
        }

        return PastePayload(string: PasteAdapterUtils.shellEscape(trimmed), rtf: nil, html: nil)
    }
}

struct XcodeAdapter: PasteAdapter {
    let adapterName = "Xcode"
    let targetBundleIDs: Set<String> = [
        "com.apple.dt.Xcode"
    ]

    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

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

struct MessagingAdapter: PasteAdapter {
    let adapterName = "Messaging"
    let targetBundleIDs: Set<String> = [
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "org.whispersystems.signal-desktop",
        "com.apple.MobileSMS",
        "com.tinyspeck.slackmacgap"
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

struct IWorkAdapter: PasteAdapter {
    let adapterName = "iWork"
    let targetBundleIDs: Set<String> = [
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote"
    ]
    
    func adapt(_ content: String, type: ClipboardItem.ItemType) -> PastePayload {
        return PastePayload(string: content, rtf: nil, html: nil)
    }
}

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

final class PasteAdapterManager {
    static let shared = PasteAdapterManager()

    private let adapterMap: [String: any PasteAdapter]

    init() {
        let allAdapters: [any PasteAdapter] = [
            MarkdownAdapter(),
            TerminalAdapter(),
            MessagingAdapter(),
            NoteAdapter(),
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

    func adaptedPayload(for bundleID: String, content: String, type: ClipboardItem.ItemType) -> PastePayload? {
        guard let adapter = adapterMap[bundleID] else { return nil }
        let payload = adapter.adapt(content, type: type)
        if payload.string == content && payload.rtf == nil && payload.html == nil {
            return nil
        }
        return payload
    }

    func adapterName(for bundleID: String) -> String? {
        adapterMap[bundleID]?.adapterName
    }
}
