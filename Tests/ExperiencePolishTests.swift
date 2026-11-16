import XCTest
import AppKit
@testable import ClipShelf

final class PopupPlacementClampTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testClampKeepsOriginInsideScreen() {
        let origin = PopupPlacement.clamp(origin: NSPoint(x: 100, y: 100), size: CGSize(width: 360, height: 440), within: screen)
        XCTAssertEqual(origin, NSPoint(x: 100, y: 100))
    }

    func testClampPullsBackFromRightEdge() {
        let origin = PopupPlacement.clamp(origin: NSPoint(x: 1400, y: 100), size: CGSize(width: 360, height: 440), within: screen)
        XCTAssertEqual(origin.x, 1440 - 360)
    }

    func testClampPullsBackFromTopEdge() {
        let origin = PopupPlacement.clamp(origin: NSPoint(x: 100, y: 800), size: CGSize(width: 360, height: 440), within: screen)
        XCTAssertEqual(origin.y, 900 - 440)
    }

    func testClampPullsBackFromLeftAndBottom() {
        let origin = PopupPlacement.clamp(origin: NSPoint(x: -50, y: -80), size: CGSize(width: 360, height: 440), within: screen)
        XCTAssertEqual(origin, NSPoint(x: 0, y: 0))
    }

    func testClampWithZeroScreenReturnsOrigin() {
        let origin = NSPoint(x: -50, y: -80)
        XCTAssertEqual(PopupPlacement.clamp(origin: origin, size: CGSize(width: 360, height: 440), within: .zero), origin)
    }

    func testOriginOnSecondaryScreenStaysOnThatScreen() {
        let parent = CGRect(x: 1500, y: 100, width: 340, height: 480)
        let origin = PopupPlacement.origin(parentFrame: parent, size: CGSize(width: 360, height: 440))
        let containing = NSScreen.screens.first { $0.frame.contains(NSPoint(x: parent.midX, y: parent.midY)) }
        if let containing {
            let visible = containing.visibleFrame
            XCTAssertGreaterThanOrEqual(origin.x, visible.minX)
            XCTAssertLessThanOrEqual(origin.x + 360, visible.maxX)
            XCTAssertGreaterThanOrEqual(origin.y, visible.minY)
            XCTAssertLessThanOrEqual(origin.y + 440, visible.maxY)
        }
    }
}

final class ImageCacheMemoryScaleTests: XCTestCase {
    func testLowMemoryMachinesGetQuarterBudget() {
        XCTAssertEqual(ImageCache.memoryScaleFactor(physicalMemory: 4 * 1_073_741_824), 0.25)
    }

    func testMidMemoryMachinesGetHalfBudget() {
        XCTAssertEqual(ImageCache.memoryScaleFactor(physicalMemory: 8 * 1_073_741_824), 0.5)
    }

    func testHighMemoryMachinesKeepFullBudget() {
        XCTAssertEqual(ImageCache.memoryScaleFactor(physicalMemory: 16 * 1_073_741_824), 1.0)
        XCTAssertEqual(ImageCache.memoryScaleFactor(physicalMemory: 32 * 1_073_741_824), 1.0)
    }
}

final class TIFFStoragePreparationTests: XCTestCase {
    private func makeTIFF() -> Data? {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image.tiffRepresentation
    }

    func testTIFFIsConvertedToPNGForStorage() throws {
        let tiff = try XCTUnwrap(makeTIFF())
        let prepared = ClipboardImageStoragePreparation.storedRepresentation(of: tiff, fileExtension: "tiff")
        XCTAssertEqual(prepared.1, "png")
        XCTAssertNotNil(NSImage(data: prepared.0))
    }

    func testPNGPassthroughUnchanged() throws {
        let tiff = try XCTUnwrap(makeTIFF())
        let png = try XCTUnwrap(ClipboardImageStoragePreparation.pngRepresentation(of: tiff))
        let prepared = ClipboardImageStoragePreparation.storedRepresentation(of: png, fileExtension: "png")
        XCTAssertEqual(prepared.1, "png")
        XCTAssertEqual(prepared.0, png)
    }
}