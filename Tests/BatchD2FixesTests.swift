import XCTest
import AppKit
@testable import ClipShelf

@MainActor
final class BatchD2FixesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PasteQueue.shared.clear()
        PasteQueue.shared.stackMode = false
    }

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

        PasteQueue.shared.stackMode = false
        pendingCompletion?(ClipboardItem(content: "", type: .image))

        XCTAssertEqual(PasteQueue.shared.queue.count, 1, "capture-time decision wins: item lands in the queue once")
    }

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
