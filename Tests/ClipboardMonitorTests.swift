import XCTest
import AppKit
@testable import ClipShelf

final class ClipboardMonitorTests: XCTestCase {

    private var testPasteboard: NSPasteboard!
    private var monitor: ClipboardMonitor!

    override func setUp() {
        super.setUp()
        testPasteboard = NSPasteboard(name: NSPasteboard.Name("com.test.ClipboardMonitor.\(UUID().uuidString)"))
        testPasteboard.clearContents()
        monitor = ClipboardMonitor(pasteboard: testPasteboard)
        monitor.start()
    }

    override func tearDown() {
        monitor.stop()
        testPasteboard.releaseGlobally()
        super.tearDown()
    }

    // MARK: - No Change

    func testNoChangeReturnsNoChange() {
        // No content written — changeCount unchanged after start
        let result = monitor.checkClipboard()
        XCTAssertEqual(result, .noChange)
    }

    // MARK: - Text Capture

    func testTextCaptureCallsOnCapture() {
        var captured: CapturedContent?
        monitor.onCapture = { captured = $0 }

        testPasteboard.clearContents()
        testPasteboard.setString("hello world", forType: .string)
        let result = monitor.checkClipboard()

        XCTAssertEqual(result, .captured)
        guard let content = captured else {
            XCTFail("onCapture should have been called")
            return
        }
        if case .text(let text) = content.kind {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("Expected text content, got \(content.kind)")
        }
    }

    // MARK: - Excluded App

    func testExcludedAppReturnsIgnored() {
        // The frontmost app during tests is the test runner (Xcode / xctest).
        // We add its bundleID to excluded list to test the exclusion path.
        let testRunnerBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !testRunnerBundleID.isEmpty else {
            // Can't determine frontmost app in CI — skip
            return
        }
        monitor.excludedBundleIDs = [testRunnerBundleID]

        testPasteboard.clearContents()
        testPasteboard.setString("secret", forType: .string)
        let result = monitor.checkClipboard()

        XCTAssertEqual(result, .ignored)
    }

    // MARK: - Duplicate Within Threshold

    func testDuplicateTextWithinThresholdIgnored() {
        var captureCount = 0
        monitor.onCapture = { _ in captureCount += 1 }

        testPasteboard.clearContents()
        testPasteboard.setString("duplicate", forType: .string)
        let r1 = monitor.checkClipboard()
        XCTAssertEqual(r1, .captured)
        XCTAssertEqual(captureCount, 1)

        // Write the same text again (simulates re-copy within 3 seconds)
        testPasteboard.clearContents()
        testPasteboard.setString("duplicate", forType: .string)
        let r2 = monitor.checkClipboard()
        XCTAssertEqual(r2, .ignored)
        XCTAssertEqual(captureCount, 1, "Duplicate text within threshold should be ignored")
    }

    // MARK: - Acknowledge Change Count

    func testAcknowledgeChangeCountPreventsCapture() {
        testPasteboard.clearContents()
        testPasteboard.setString("acknowledged", forType: .string)
        monitor.acknowledgeChangeCount()

        let result = monitor.checkClipboard()
        XCTAssertEqual(result, .noChange, "After acknowledgeChangeCount, checkClipboard should see no change")
    }

    // MARK: - Distinct Text Captured

    func testDistinctTextCapturedSequentially() {
        var texts: [String] = []
        monitor.onCapture = { content in
            if case .text(let text) = content.kind { texts.append(text) }
        }

        testPasteboard.clearContents()
        testPasteboard.setString("first", forType: .string)
        _ = monitor.checkClipboard()

        // Wait to exceed the 3-second dedup window
        Thread.sleep(forTimeInterval: 3.1)

        testPasteboard.clearContents()
        testPasteboard.setString("second", forType: .string)
        _ = monitor.checkClipboard()

        XCTAssertEqual(texts, ["first", "second"])
    }

    // MARK: - Text Preferred Over Image

    func testTextPreferredOverImage() {
        var captured: CapturedContent?
        monitor.onCapture = { captured = $0 }

        testPasteboard.clearContents()
        // Write both text and TIFF image — text should win
        let tinyImage = NSImage(size: NSSize(width: 1, height: 1))
        testPasteboard.writeObjects(["hello from text" as NSString, tinyImage])
        let result = monitor.checkClipboard()

        XCTAssertEqual(result, .captured)
        guard let content = captured else {
            XCTFail("onCapture should have been called")
            return
        }
        if case .text(let text) = content.kind {
            XCTAssertEqual(text, "hello from text")
        } else {
            XCTFail("Expected text content when both text and image are present, got \(content.kind)")
        }
    }

    func testJPEGCapturePreservesEncodedData() {
        var captured: CapturedContent?
        monitor.onCapture = { captured = $0 }
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

        testPasteboard.clearContents()
        testPasteboard.setData(jpegData, forType: NSPasteboard.PasteboardType("public.jpeg"))
        let result = monitor.checkClipboard()

        XCTAssertEqual(result, .captured)
        guard let content = captured else {
            XCTFail("onCapture should have been called")
            return
        }
        if case .imageFile(let data, let fileExtension) = content.kind {
            XCTAssertEqual(data, jpegData)
            XCTAssertEqual(fileExtension, "jpg")
        } else {
            XCTFail("Expected imageFile content, got \(content.kind)")
        }
    }

    // MARK: - File URL Capture

    func testFileURLCapture() {
        var captured: CapturedContent?
        monitor.onCapture = { captured = $0 }

        testPasteboard.clearContents()
        let fileURL = URL(fileURLWithPath: "/tmp/test-file.txt")
        testPasteboard.writeObjects([fileURL as NSURL])
        let result = monitor.checkClipboard()

        XCTAssertEqual(result, .captured)
        guard let content = captured else {
            XCTFail("onCapture should have been called")
            return
        }
        if case .fileURL(let paths) = content.kind {
            XCTAssertTrue(paths.contains("/tmp/test-file.txt"), "File URL should be captured as a file path")
        } else {
            XCTFail("Expected file URL content, got \(content.kind)")
        }
    }
}

// MARK: - CheckOutcome Equatable
extension ClipboardMonitor.CheckOutcome: @retroactive Equatable {
    public static func == (lhs: ClipboardMonitor.CheckOutcome, rhs: ClipboardMonitor.CheckOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.noChange, .noChange), (.captured, .captured), (.ignored, .ignored): return true
        default: return false
        }
    }
}
