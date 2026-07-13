import XCTest
@testable import ClipboardManager

@MainActor
final class ClipboardRuleEngineTests: XCTestCase {

    private var engine: ClipboardRuleEngine!

    override func setUp() {
        super.setUp()
        engine = ClipboardRuleEngine()
    }

    // MARK: - Strip URL Tracking

    func testStripURLTrackingRemovesUTMParams() async {
        engine.rules = [
            ClipboardRule(name: "strip", actions: [.stripURLTracking], order: 0)
        ]
        let input = text("https://example.com/page?utm_source=twitter&utm_medium=social&id=42")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertEqual(t, "https://example.com/page?id=42")
        } else {
            XCTFail("Expected .store with cleaned URL")
        }
    }

    func testStripURLTrackingRemovesFbclid() async {
        engine.rules = [
            ClipboardRule(name: "strip", actions: [.stripURLTracking], order: 0)
        ]
        let input = text("https://example.com/?fbclid=abc123")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertFalse(t.contains("fbclid"))
            XCTAssertEqual(t, "https://example.com/")
        } else {
            XCTFail("Expected .store with cleaned URL")
        }
    }

    func testStripURLTrackingPreservesNonTrackingParams() async {
        engine.rules = [
            ClipboardRule(name: "strip", actions: [.stripURLTracking], order: 0)
        ]
        let input = text("https://example.com/search?q=swift&page=2")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertTrue(t.contains("q=swift"))
            XCTAssertTrue(t.contains("page=2"))
        } else {
            XCTFail("Expected .store")
        }
    }

    func testStripURLTrackingIgnoresNonURL() async {
        engine.rules = [
            ClipboardRule(name: "strip", actions: [.stripURLTracking], order: 0)
        ]
        let input = text("hello world utm_source")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertEqual(t, "hello world utm_source")
        } else {
            XCTFail("Expected .store with unchanged text")
        }
    }

    // MARK: - Sensitive Content Detection

    func testDetectCreditCardNumber() async {
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: 60)], order: 0)
        ]
        let input = text("My card is 4111 1111 1111 1111")
        let result = await engine.process(input)
        if case .storeSensitive(_, let ttl) = result {
            XCTAssertEqual(ttl, 60)
        } else {
            XCTFail("Expected .storeSensitive, got \(result)")
        }
    }

    func testDetectAWSKey() async {
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: 30)], order: 0)
        ]
        let input = text("AKIAIOSFODNN7EXAMPLE")
        let result = await engine.process(input)
        if case .storeSensitive(_, let ttl) = result {
            XCTAssertEqual(ttl, 30)
        } else {
            XCTFail("Expected .storeSensitive for AWS key")
        }
    }

    func testDetectSSHPrivateKey() async {
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: nil)], order: 0)
        ]
        let input = text("-----BEGIN RSA PRIVATE KEY-----\nMIIEow...")
        let result = await engine.process(input)
        if case .storeSensitive = result {
            // pass
        } else {
            XCTFail("Expected .storeSensitive for SSH key")
        }
    }

    func testNonSensitiveContentPassesThrough() async {
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: 60)], order: 0)
        ]
        let input = text("Just a normal sentence")
        let result = await engine.process(input)
        if case .store = result {
            // pass
        } else {
            XCTFail("Expected .store for non-sensitive content")
        }
    }

    // MARK: - Discard

    func testDiscardRuleShortCircuits() async {
        engine.rules = [
            ClipboardRule(name: "discard-all", trigger: .contentMatches(pattern: "secret"), actions: [.discard], order: 0),
            ClipboardRule(name: "pin-all", actions: [.autoPin], order: 1)
        ]
        let input = text("this is a secret message")
        let result = await engine.process(input)
        XCTAssertEqual(result, .discard)
    }

    func testDiscardDoesNotMatchNonMatchingContent() async {
        engine.rules = [
            ClipboardRule(name: "discard-secret", trigger: .contentMatches(pattern: "secret"), actions: [.discard], order: 0)
        ]
        let input = text("hello world")
        let result = await engine.process(input)
        if case .store = result {
            // pass
        } else {
            XCTFail("Expected .store for non-matching content")
        }
    }

    // MARK: - Rule Chaining

    func testMultipleActionsChain() async {
        engine.rules = [
            ClipboardRule(name: "chain", actions: [.stripURLTracking, .trimWhitespace], order: 0)
        ]
        let input = text("  https://example.com/?utm_source=test  ")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertFalse(t.contains("utm_source"))
            XCTAssertEqual(t, t.trimmingCharacters(in: .whitespaces))
        } else {
            XCTFail("Expected .store with chained transforms")
        }
    }

    func testRegexReplaceAction() async {
        engine.rules = [
            ClipboardRule(name: "regex", actions: [.replaceRegex(pattern: "\\d+", replacement: "#")], order: 0)
        ]
        let input = text("Order 12345 shipped")
        let result = await engine.process(input)
        if case .store(let c) = result, case .text(let t) = c.kind {
            XCTAssertEqual(t, "Order # shipped")
        } else {
            XCTFail("Expected .store with regex replacement")
        }
    }

    // MARK: - Trigger Matching

    func testContentMatchesTrigger() async {
        engine.rules = [
            ClipboardRule(name: "pin-urls", trigger: .contentMatches(pattern: "^https?://"), actions: [.autoPin], order: 0)
        ]
        let result = await engine.process(text("https://swift.org"))
        XCTAssertEqual(result, .pin(text("https://swift.org")))
    }

    func testSourceAppTrigger() async {
        engine.rules = [
            ClipboardRule(name: "from-safari", trigger: .sourceApp(bundleID: "com.apple.Safari"), actions: [.autoPin], order: 0)
        ]
        let safariContent = CapturedContent(kind: .text(content: "hello"), sourceBundleID: "com.apple.Safari", sourceAppName: "Safari")
        let result = await engine.process(safariContent)
        XCTAssertEqual(result, .pin(safariContent))

        let chromeContent = CapturedContent(kind: .text(content: "hello"), sourceBundleID: "com.google.Chrome", sourceAppName: "Chrome")
        let result2 = await engine.process(chromeContent)
        if case .store = result2 {} else { XCTFail("Expected .store for non-matching app") }
    }

    func testContentTypeTrigger() async {
        engine.rules = [
            ClipboardRule(name: "pin-images", trigger: .contentType(.image), actions: [.autoPin], order: 0)
        ]
        let imageContent = CapturedContent(kind: .image(data: Data([0xFF])), sourceBundleID: nil, sourceAppName: nil)
        let result = await engine.process(imageContent)
        XCTAssertEqual(result, .pin(imageContent))

        let imageFileContent = CapturedContent(kind: .imageFile(data: Data([0xFF, 0xD8]), fileExtension: "jpg"), sourceBundleID: nil, sourceAppName: nil)
        let result3 = await engine.process(imageFileContent)
        XCTAssertEqual(result3, .pin(imageFileContent))

        let textContent = CapturedContent(kind: .text(content: "hello"), sourceBundleID: nil, sourceAppName: nil)
        let result2 = await engine.process(textContent)
        if case .store = result2 {} else { XCTFail("Expected .store for text when trigger is image") }
    }

    func testDisabledRuleIsSkipped() async {
        engine.rules = [
            ClipboardRule(name: "disabled", isEnabled: false, actions: [.discard], order: 0)
        ]
        let result = await engine.process(text("anything"))
        if case .store = result {} else { XCTFail("Expected .store since rule is disabled") }
    }

    // MARK: - Helpers

    private func text(_ s: String) -> CapturedContent {
        CapturedContent(kind: .text(content: s), sourceBundleID: nil, sourceAppName: nil)
    }
}
