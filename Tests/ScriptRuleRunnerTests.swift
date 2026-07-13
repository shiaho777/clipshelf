import XCTest
@testable import ClipShelf

@MainActor
final class ScriptRuleRunnerTests: XCTestCase {
    var runner: ScriptRuleRunner!

    override func setUp() {
        super.setUp()
        runner = ScriptRuleRunner()
    }

    func testPassthrough() async {
        let script = "function process(content, bundleID) { return content; }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertEqual(result, .passthrough)
    }

    func testModified() async {
        let script = "function process(content, bundleID) { return content.toUpperCase(); }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertEqual(result, .modified("HELLO"))
    }

    func testDiscard() async {
        let script = "function process(content, bundleID) { return null; }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertEqual(result, .discard)
    }

    func testBundleIDPassedThrough() async {
        let script = "function process(content, bundleID) { return bundleID; }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: "com.example.app")
        XCTAssertEqual(result, .modified("com.example.app"))
    }

    func testNilBundleID() async {
        let script = "function process(content, bundleID) { return bundleID === null ? 'yes' : 'no'; }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertEqual(result, .modified("yes"))
    }

    func testSyntaxErrorReturnsNil() async {
        let script = "function process(content { return content; }"  // missing )
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertNil(result)
    }

    func testMissingProcessFunctionReturnsNil() async {
        let script = "function foo(content) { return content; }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertNil(result)
    }

    func testRuntimeErrorReturnsNil() async {
        let script = "function process(content, bundleID) { return undefinedVar.method(); }"
        let result = await runner.evaluate(script: script, content: "hello", sourceBundleID: nil)
        XCTAssertNil(result)
    }

    func testStringManipulation() async {
        let script = """
        function process(content, bundleID) {
            return content.replace(/\\s+/g, ' ').trim();
        }
        """
        let result = await runner.evaluate(script: script, content: "  hello   world  ", sourceBundleID: nil)
        XCTAssertEqual(result, .modified("hello world"))
    }

    func testJSONFormatting() async {
        let script = """
        function process(content, bundleID) {
            try { return JSON.stringify(JSON.parse(content), null, 2); }
            catch(e) { return content; }
        }
        """
        let result = await runner.evaluate(script: script, content: "{\"a\":1}", sourceBundleID: nil)
        XCTAssertEqual(result, .modified("{\n  \"a\": 1\n}"))
    }

    func testConditionalDiscardByApp() async {
        let script = """
        function process(content, bundleID) {
            if (bundleID === 'com.secret.app') return null;
            return content;
        }
        """
        let keep = await runner.evaluate(script: script, content: "hello", sourceBundleID: "com.normal.app")
        XCTAssertEqual(keep, .passthrough)

        let discard = await runner.evaluate(script: script, content: "hello", sourceBundleID: "com.secret.app")
        XCTAssertEqual(discard, .discard)
    }

    func testRuleEngineIntegrationWithScript() async {
        let engine = ClipboardRuleEngine()
        let script = "function process(content, bundleID) { return content.toUpperCase(); }"
        engine.rules = [
            ClipboardRule(name: "Test Script", trigger: .always, actions: [.runScript(source: script)])
        ]
        let content = CapturedContent(kind: .text(content: "hello"), sourceBundleID: nil, sourceAppName: nil)
        let result = await engine.process(content)

        if case .store(let processed) = result, case .text(let text) = processed.kind {
            XCTAssertEqual(text, "HELLO")
        } else {
            XCTFail("Expected .store with modified text, got \(result)")
        }
    }

    func testRuleEngineScriptDiscard() async {
        let engine = ClipboardRuleEngine()
        let script = "function process(content, bundleID) { return null; }"
        engine.rules = [
            ClipboardRule(name: "Discard Script", trigger: .always, actions: [.runScript(source: script)])
        ]
        let content = CapturedContent(kind: .text(content: "hello"), sourceBundleID: nil, sourceAppName: nil)
        let result = await engine.process(content)
        XCTAssertEqual(result, .discard)
    }
}
