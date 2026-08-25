import XCTest
import AppKit
import Carbon.HIToolbox
@testable import ClipShelf

/// Regression tests for robustness fixes: hotkey config restoration, JS
/// hang quarantine, pasteboard write failure semantics, CSV formula
/// injection, and encryption key initialization.
final class RobustnessFixesTests: XCTestCase {

    // MARK: - HotKeyManager config restoration

    /// Loading a stored config must not persist still-default values over
    /// customizations that have not been read yet. Before the fix, assigning
    /// `mainHotKey` during load fired `didSet` → `saveConfig()`, clobbering
    /// the queue/quick-paste keys on disk.
    func testLoadConfigPreservesStoredCustomizations() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hotkey-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = JSONHotKeyStore(storageDirectory: directory)
        try writer.saveMainHotKey(HotKeyConfig(keyCode: 11, modifiers: UInt32(controlKey | optionKey)))
        try writer.saveQueueHotKey(HotKeyConfig(keyCode: 12, modifiers: UInt32(shiftKey)))
        try writer.saveQuickPasteHotKey(HotKeyConfig(keyCode: 13, modifiers: UInt32(controlKey)))

        let manager = HotKeyManager(storageDirectory: directory, hotKeyStore: writer)
        XCTAssertEqual(manager.mainHotKey.keyCode, 11)
        XCTAssertEqual(manager.queueHotKey.keyCode, 12)
        XCTAssertEqual(manager.quickPasteHotKey.keyCode, 13)

        // Re-read from disk through a fresh store to prove nothing was rewritten.
        let reloaded = JSONHotKeyStore(storageDirectory: directory)
        XCTAssertEqual(try reloaded.loadMainHotKey()?.keyCode, 11)
        XCTAssertEqual(try reloaded.loadQueueHotKey()?.keyCode, 12)
        XCTAssertEqual(try reloaded.loadQuickPasteHotKey()?.keyCode, 13)
    }

    // MARK: - ScriptRuleRunner hang containment

    /// A script stuck in an infinite loop must time out without poisoning all
    /// later evaluations (the serial eval queue is rotated) and must be
    /// skipped immediately on subsequent calls.
    func testInfiniteLoopIsQuarantinedWithoutBlockingLaterScripts() async {
        let runner = ScriptRuleRunner(timeout: 0.5)
        let hangScript = "function process(content, bundleID) { while(true) {} }"

        let hungStart = Date()
        let hungResult = await runner.evaluate(script: hangScript, content: "x", sourceBundleID: nil)
        XCTAssertNil(hungResult)
        XCTAssertGreaterThan(Date().timeIntervalSince(hungStart), 0.4,
                             "expected to wait for the timeout before returning")

        // The queue rotation lets healthy scripts keep working.
        let healthy = await runner.evaluate(
            script: "function process(content, bundleID) { return content + '!'; }",
            content: "hi",
            sourceBundleID: nil
        )
        XCTAssertEqual(healthy, .modified("hi!"))

        // The hung script is quarantined and returns instantly.
        let quarantinedStart = Date()
        let quarantined = await runner.evaluate(script: hangScript, content: "x", sourceBundleID: nil)
        XCTAssertNil(quarantined)
        XCTAssertLessThan(Date().timeIntervalSince(quarantinedStart), 0.3,
                          "quarantined script should be skipped without waiting for timeout")
    }

    // MARK: - ClipboardPasteboardWriter failure semantics

    /// When an image payload cannot be resolved the pasteboard must be left
    /// untouched — previously it was cleared first, destroying whatever the
    /// user had copied, and the use count was incremented anyway.
    func testFailedImagePayloadLeavesClipboardUntouched() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("clipshelf-test-\(UUID().uuidString)"))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("keep me", forType: .string)
        let changeCountBefore = pasteboard.changeCount

        let item = ClipboardItem(content: "", type: .image)
        let result = ClipboardPasteboardWriter.write(
            item: item,
            to: pasteboard,
            autoPaste: false,
            asPlainText: false,
            smartPasteEnabled: true,
            targetBundleID: nil,
            imagePayload: { nil }
        )

        XCTAssertFalse(result.didWrite)
        XCTAssertEqual(pasteboard.changeCount, changeCountBefore)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testTextItemWritesAndReportsSuccess() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("clipshelf-test-\(UUID().uuidString)"))
        let item = ClipboardItem(content: "hello world", type: .text)

        let result = ClipboardPasteboardWriter.write(
            item: item,
            to: pasteboard,
            autoPaste: false,
            asPlainText: false,
            smartPasteEnabled: true,
            targetBundleID: nil,
            imagePayload: nil
        )

        XCTAssertTrue(result.didWrite)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    // MARK: - CSV formula injection

    func testCSVFormulaInjectionNeutralized() {
        XCTAssertEqual("=1+1".csvEscaped, "'=1+1")
        XCTAssertEqual("+SUM(A1)".csvEscaped, "'+SUM(A1)")
        XCTAssertEqual("-not-a-flag".csvEscaped, "'-not-a-flag")
        XCTAssertEqual("@import".csvEscaped, "'@import")
        XCTAssertEqual("\tTabbed".csvEscaped, "'\tTabbed")
        // Ordinary content is untouched.
        XCTAssertEqual("plain text".csvEscaped, "plain text")
        // Quoting still applies after neutralization.
        XCTAssertEqual("=a,b".csvEscaped, "\"'=a,b\"")
    }

    // MARK: - EncryptionService concurrency

    /// Concurrent first use from multiple queues must initialize the key
    /// exactly once without crashing (previously an unsynchronized lazy var).
    func testConcurrentEncryptionDoesNotCrash() {
        let service = EncryptionService.shared
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "encryption-concurrency-test", attributes: .concurrent)

        for index in 0..<32 {
            group.enter()
            queue.async {
                defer { group.leave() }
                if let sealed = try? service.encrypt(Data("payload-\(index)".utf8)) {
                    _ = try? service.decrypt(sealed)
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
    }
}
