import XCTest
@testable import ClipShelf

final class PasteAdapterTests: XCTestCase {
    
    // MARK: - MarkdownAdapter
    
    func testMarkdownAdapterFormatsURL() {
        let adapter = MarkdownAdapter()
        let result = adapter.adapt("https://www.swift.org/documentation", type: .text)
        XCTAssertEqual(result.string, "[swift.org](https://www.swift.org/documentation)")
    }
    
    func testMarkdownAdapterFormatsURLWithoutWWW() {
        let adapter = MarkdownAdapter()
        let result = adapter.adapt("https://github.com/apple/swift", type: .text)
        XCTAssertEqual(result.string, "[github.com](https://github.com/apple/swift)")
    }
    
    func testMarkdownAdapterWrapsCodeInFences() {
        let adapter = MarkdownAdapter()
        let code = "func hello() {\n    print(\"hi\")\n    return\n}"
        let result = adapter.adapt(code, type: .text)
        XCTAssertTrue(result.string?.hasPrefix("```\n") ?? false)
        XCTAssertTrue(result.string?.hasSuffix("\n```") ?? false)
    }
    
    func testMarkdownAdapterPassesThroughPlainText() {
        let adapter = MarkdownAdapter()
        let result = adapter.adapt("just some text", type: .text)
        XCTAssertEqual(result.string, "just some text")
    }
    
    func testMarkdownAdapterTargetsVSCode() {
        let adapter = MarkdownAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.microsoft.VSCode"))
        XCTAssertTrue(adapter.targetBundleIDs.contains("md.obsidian"))
    }
    
    // MARK: - TerminalAdapter
    
    func testTerminalAdapterEscapesDangerousChars() {
        let adapter = TerminalAdapter()
        let result = adapter.adapt("echo $HOME", type: .text)
        XCTAssertEqual(result.string, "'echo $HOME'")
    }
    
    func testTerminalAdapterEscapesSingleQuotes() {
        let adapter = TerminalAdapter()
        let result = adapter.adapt("it's a $test", type: .text)
        XCTAssertEqual(result.string, "'it'\\''s a $test'")
    }
    
    func testTerminalAdapterPassesThroughSafeText() {
        let adapter = TerminalAdapter()
        let result = adapter.adapt("ls -la", type: .text)
        XCTAssertEqual(result.string, "ls -la")
    }
    
    func testTerminalAdapterTargetsAppleTerminal() {
        let adapter = TerminalAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.apple.Terminal"))
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.googlecode.iterm2"))
        XCTAssertTrue(adapter.targetBundleIDs.contains("dev.warp.Warp-Stable"))
    }
    
    // MARK: - MessagingAdapter (replaces former SlackAdapter)
    
    func testMessagingAdapterWrapsMultiLineCodeForSlack() {
        let adapter = MessagingAdapter()
        let code = "func hello() {\n    return 42\n}"
        let result = adapter.adapt(code, type: .text)
        XCTAssertTrue(result.string?.hasPrefix("```") ?? false)
        XCTAssertTrue(result.string?.hasSuffix("```") ?? false)
    }
    
    func testMessagingAdapterWrapsSingleLineCodeForSlack() {
        let adapter = MessagingAdapter()
        let result = adapter.adapt("let x = 42", type: .text)
        XCTAssertEqual(result.string, "let x = 42")
    }
    
    func testMessagingAdapterPassesThroughPlainText() {
        let adapter = MessagingAdapter()
        let result = adapter.adapt("hello world", type: .text)
        XCTAssertEqual(result.string, "hello world")
    }

    func testMessagingAdapterTargetsSlack() {
        let adapter = MessagingAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.tinyspeck.slackmacgap"))
    }
    
    // MARK: - PasteAdapterManager
    
    func testManagerReturnsPayloadForMatchingApp() {
        let manager = PasteAdapterManager.shared
        let result = manager.adaptedPayload(for: "com.microsoft.VSCode", content: "https://swift.org", type: .text)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.string?.contains("[swift.org]") ?? false)
    }
    
    func testManagerReturnsNilForUnknownApp() {
        let manager = PasteAdapterManager.shared
        let result = manager.adaptedPayload(for: "com.unknown.App", content: "hello", type: .text)
        XCTAssertNil(result)
    }
    
    func testManagerReturnsNilWhenContentUnchanged() {
        let manager = PasteAdapterManager.shared
        // MarkdownAdapter won't change plain text
        let result = manager.adaptedPayload(for: "com.microsoft.VSCode", content: "just text", type: .text)
        XCTAssertNil(result)
    }

    // MARK: - PasteAdapterUtils

    func testLooksLikeCodeDetectsSwift() {
        XCTAssertTrue(PasteAdapterUtils.looksLikeCode("func hello() {\n    return 1\n}"))
    }

    func testLooksLikeCodeDetectsPython() {
        XCTAssertTrue(PasteAdapterUtils.looksLikeCode("def hello():\n    return 1"))
    }

    func testLooksLikeCodeRejectsPlainText() {
        XCTAssertFalse(PasteAdapterUtils.looksLikeCode("hello world"))
    }

    func testNeedsShellEscapingDetectsDollarSign() {
        XCTAssertTrue(PasteAdapterUtils.needsShellEscaping("echo $HOME"))
    }

    func testNeedsShellEscapingPassesSafeText() {
        XCTAssertFalse(PasteAdapterUtils.needsShellEscaping("ls -la"))
    }

    func testShellEscapeWrapsSingleQuotes() {
        XCTAssertEqual(PasteAdapterUtils.shellEscape("hello"), "'hello'")
    }

    func testShellEscapeHandlesExistingSingleQuotes() {
        XCTAssertEqual(PasteAdapterUtils.shellEscape("it's"), "'it'\\''s'")
    }

    // MARK: - Merged TerminalAdapter targets

    func testTerminalAdapterIncludesHyper() {
        let adapter = TerminalAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("co.zeit.hyper"))
    }

    func testTerminalAdapterIncludesRio() {
        let adapter = TerminalAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.raphaelamorim.rio"))
    }

    func testTerminalAdapterIncludesWezTerm() {
        let adapter = TerminalAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.github.wez.wezterm"))
    }

    // MARK: - MessagingAdapter

    func testMessagingAdapterWrapsMultiLineCodeInTripleBackticks() {
        let adapter = MessagingAdapter()
        let code = "func hello() {\n    return 42\n}"
        let result = adapter.adapt(code, type: .text)
        XCTAssertTrue(result.string?.hasPrefix("```") ?? false)
    }

    func testMessagingAdapterWrapsSingleLineCodeInBackticks() {
        let adapter = MessagingAdapter()
        let result = adapter.adapt("let x = 42", type: .text)
        XCTAssertEqual(result.string, "let x = 42")
    }

    func testMessagingAdapterTargetsDiscord() {
        let adapter = MessagingAdapter()
        XCTAssertTrue(adapter.targetBundleIDs.contains("com.hnc.Discord"))
    }
}
