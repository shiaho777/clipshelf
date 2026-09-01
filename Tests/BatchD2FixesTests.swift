import XCTest
import AppKit
@testable import ClipShelf

/// Regression tests for batch D2 fixes.
@MainActor
final class BatchD2FixesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // PasteQueue is a process-wide singleton; earlier tests may have left
        // items behind, and assertions count its contents.
        PasteQueue.shared.clear()
        PasteQueue.shared.stackMode = false
    }

    // MARK: - S14: stackMode snapshot at dispatch time

    /// The dispatcher must snapshot `stackMode` when a capture arrives, not
    /// re-read it after insertion completes. Toggling stack mode off while an
    /// async image capture is in flight must not enqueue that capture.
    /// The dispatcher must snapshot `stackMode` when a capture arrives, not
    /// re-read it after insertion completes. A capture that arrived while
    /// stack mode was ON stays enqueued even if the user toggles OFF while
    /// the async image insert is in flight — and vice versa, a capture that
    /// arrived while OFF must not be enqueued when the completion re-checks
    /// stackMode (now ON). The toggle decision belongs to capture time.
    func testCaptureWhileStackModeOnEnqueuesDespiteTogglingOffMidFlight() {
        var pendingCompletion: ((ClipboardItem) -> Void)?
        let dispatcher = ClipboardCaptureDispatcher(
            addText: { content, _, _, _, _, _ in ClipboardItem(content: content, type: .text) },
            addRichText: { content, rtf, _, _, _, _, _ in ClipboardItem(content: content, rtfData: rtf, type: .richText) },
            addImage: { _, _, _, _, _, completion in pendingCompletion = completion },
            addFileURL: { paths, _, _, _, _, _, _ in ClipboardItem(content: paths.joined(), type: .fileURL) }
        )

        PasteQueue.shared.stackMode = true
        dispatcher.dispatch(
            CapturedContent(kind: .image(data: smallPNG()), sourceBundleID: nil, sourceAppName: nil)
        )

        // Insertion is still in flight; the user turns stack mode off. The
        // item was already captured under stack mode, so the queued copy must
        // still appear exactly once (the old code enqueued it; a naive
        // "check again at completion" alternative would silently drop it).
        PasteQueue.shared.stackMode = false
        pendingCompletion?(ClipboardItem(content: "", type: .image))

        XCTAssertEqual(PasteQueue.shared.queue.count, 1, "capture-time decision wins: item lands in the queue once")
    }

    /// The inverse half of the race: with stack mode OFF at capture time, the
    /// in-flight completion must NOT read the now-ON stackMode and enqueue.
    func testCaptureWhileStackModeOffDoesNotEnqueueOnLaterCompletion() {
        var pendingCompletion: ((ClipboardItem) -> Void)?
        let dispatcher = ClipboardCaptureDispatcher(
            addText: { content, _, _, _, _, _ in ClipboardItem(content: content, type: .text) },
            addRichText: { content, rtf, _, _, _, _, _ in ClipboardItem(content: content, rtfData: rtf, type: .richText) },
            addImage: { _, _, _, _, _, completion in pendingCompletion = completion },
            addFileURL: { paths, _, _, _, _, _, _ in ClipboardItem(content: paths.joined(), type: .fileURL) }
        )

        PasteQueue.shared.stackMode = false
        dispatcher.dispatch(
            CapturedContent(kind: .image(data: smallPNG()), sourceBundleID: nil, sourceAppName: nil)
        )

        // The user turns stack mode ON while the image insert is in flight;
        // the completion runs afterwards. It must not enqueue.
        PasteQueue.shared.stackMode = true
        defer { PasteQueue.shared.stackMode = false }
        pendingCompletion?(ClipboardItem(content: "", type: .image))

        XCTAssertEqual(PasteQueue.shared.queue.count, 0, "capture-time decision wins: item stays out of the queue")
    }

    func testStackModeOffCaptureDoesNotEnqueueText() {
        let dispatcher = makeSyncDispatcher()
        PasteQueue.shared.stackMode = false

        dispatcher.dispatch(CapturedContent(kind: .text(content: "plain"), sourceBundleID: nil, sourceAppName: nil))

        XCTAssertEqual(PasteQueue.shared.queue.count, 0)
    }

    func testStackModeCaptureEnqueuesText() {
        let dispatcher = makeSyncDispatcher()
        PasteQueue.shared.stackMode = true
        defer { PasteQueue.shared.stackMode = false }

        dispatcher.dispatch(CapturedContent(kind: .text(content: "stacked"), sourceBundleID: nil, sourceAppName: nil))

        XCTAssertEqual(PasteQueue.shared.queue.count, 1)
        XCTAssertEqual(PasteQueue.shared.queue.last?.content, "stacked")
    }

    // MARK: - Helpers

    private func makeSyncDispatcher() -> ClipboardCaptureDispatcher {
        ClipboardCaptureDispatcher(
            addText: { content, _, _, _, _, _ in ClipboardItem(content: content, type: .text) },
            addRichText: { content, rtf, _, _, _, _, _ in ClipboardItem(content: content, rtfData: rtf, type: .richText) },
            addImage: { _, _, _, _, _, completion in completion?(ClipboardItem(content: "", type: .image)) },
            addFileURL: { paths, _, _, _, _, _, _ in ClipboardItem(content: paths.joined(), type: .fileURL) }
        )
    }

    private func smallPNG() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
