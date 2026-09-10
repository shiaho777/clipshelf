import XCTest
@testable import ClipShelf

@MainActor
final class BatchD3FixesTests: XCTestCase {

    func testSensitiveContentWithAutoPinRuleKeepsPin() async {
        let engine = ClipboardRuleEngine()
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: nil)], order: 0),
            ClipboardRule(name: "pin", actions: [.autoPin], order: 1)
        ]

        let input = CapturedContent(kind: .text(content: "AKIAIOSFODNN7EXAMPLE"), sourceBundleID: nil, sourceAppName: nil)
        let result = await engine.process(input)

        guard case .storeSensitive(_, _, let pin) = result else {
            XCTFail("Expected .storeSensitive, got \(result)")
            return
        }
        XCTAssertTrue(pin, "autoPin fired alongside detectSensitive — the stored item must be pinned")
    }

    func testSensitiveContentWithoutAutoPinIsNotPinned() async {
        let engine = ClipboardRuleEngine()
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: 30)], order: 0)
        ]

        let input = CapturedContent(kind: .text(content: "AKIAIOSFODNN7EXAMPLE"), sourceBundleID: nil, sourceAppName: nil)
        let result = await engine.process(input)

        guard case .storeSensitive(_, _, let pin) = result else {
            XCTFail("Expected .storeSensitive, got \(result)")
            return
        }
        XCTAssertFalse(pin)
    }

    func testUpdateItemContentBumpsHistoryRevision() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mgr = ClipboardManager(
            storageDirectory: tempDir,
            startRuntimeServices: false,
            historyStore: InMemoryClipboardHistoryStore(),
            imageStore: InMemoryClipboardImageStore(),
            preferencesStore: InMemoryAppPreferencesStore(),
            ocrService: InMemoryOCRService()
        )
        mgr.addTextItem(content: "before")
        let revisionBefore = mgr.historyRevision

        let item = mgr.items[0]
        mgr.updateItemContent(item, newContent: "after")

        XCTAssertGreaterThan(mgr.historyRevision, revisionBefore,
                             "content edit must publish a history revision")
        XCTAssertEqual(mgr.items[0].content, "after")
    }

    func testTestProcessReportsSensitivePlusPin() async {
        let engine = ClipboardRuleEngine()
        engine.rules = [
            ClipboardRule(name: "sensitive", actions: [.detectSensitive(autoDeleteSeconds: nil)], order: 0),
            ClipboardRule(name: "pin", actions: [.autoPin], order: 1)
        ]

        let result = await engine.testProcess(text: "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(result.outcome, "sensitive+pin")
    }
}
