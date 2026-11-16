import XCTest
import AppKit
@testable import ClipShelf

final class DataCompressionTests: XCTestCase {
    func testRoundTripRepetitiveText() throws {
        let original = Data(String(repeating: "clipboard history line\n", count: 5_000).utf8)
        let compressed = try DataCompression.compress(original)
        XCTAssertLessThan(compressed.count, original.count / 10)
        let restored = try DataCompression.decompress(compressed, expectedSize: original.count)
        XCTAssertEqual(restored, original)
    }

    func testEmptyDataRoundTrip() throws {
        let compressed = try DataCompression.compress(Data())
        XCTAssertEqual(compressed.count, 0)
        XCTAssertEqual(try DataCompression.decompress(compressed, expectedSize: 0), Data())
    }

    func testRandomDataRoundTrip() throws {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let original = Data(bytes)
        let compressed = try DataCompression.compress(original)
        let restored = try DataCompression.decompress(compressed, expectedSize: original.count)
        XCTAssertEqual(restored, original)
    }

    func testTruncatedStreamNeverYieldsFullData() throws {
        let original = Data(String(repeating: "abc", count: 1_000).utf8)
        let compressed = try DataCompression.compress(original)
        let truncated = Data(compressed.prefix(compressed.count / 2))
        if let restored = try? DataCompression.decompress(truncated, expectedSize: original.count) {
            XCTAssertNotEqual(restored, original)
        }
    }

    func testWrongExpectedSizeThrows() throws {
        let original = Data(String(repeating: "abc", count: 1_000).utf8)
        let compressed = try DataCompression.compress(original)
        XCTAssertThrowsError(try DataCompression.decompress(compressed, expectedSize: original.count + 1))
    }
}

final class CompactBackupTests: XCTestCase {
    private var tempDir: URL!
    private var imageStore: InMemoryClipboardImageStore!
    private var service: DataPortService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        imageStore = InMemoryClipboardImageStore()
        service = DataPortService(
            storageDirectory: tempDir,
            historyStore: InMemoryClipboardHistoryStore(),
            imageStore: imageStore
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makePNG() -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:]) ?? Data()
    }

    private func makeItems() -> [ClipboardItem] {
        var items = (0..<200).map { i in
            ClipboardItem(content: "backup item \(i) with some repeated text", type: .text, sourceAppName: "Safari")
        }
        let png = makePNG()
        try? imageStore.saveImageData(png, fileName: "img-0.png")
        items.append(ClipboardItem(content: "", imageData: nil, type: .image, imageHash: "h0", imageFileName: "img-0.png"))
        items.append(ClipboardItem(content: "secret", type: .text, isSensitive: true))
        return items
    }

    func testCompactRoundTripPreservesItemsAndImages() throws {
        let items = makeItems()
        let url = tempDir.appendingPathComponent("backup.csb")
        try service.exportCompactBackup(to: url, items: items)
        XCTAssertTrue(CompactBackupCodec.isCompactBackup(url))

        let freshImageStore = InMemoryClipboardImageStore()
        let freshService = DataPortService(storageDirectory: tempDir, historyStore: InMemoryClipboardHistoryStore(), imageStore: freshImageStore)
        let imported = try freshService.importBackup(from: url, existingItems: [], mode: .replace)
        XCTAssertEqual(imported.count, items.filter { !$0.isSensitive }.count)
        XCTAssertFalse(imported.contains(where: { $0.isSensitive }))
        XCTAssertNotNil(freshImageStore.imageData(for: "img-0.png"))
        XCTAssertEqual(freshImageStore.imageData(for: "img-0.png"), imageStore.imageData(for: "img-0.png"))
    }

    func testCompactBackupSmallerThanLegacyZip() throws {
        let items = makeItems()
        let compactURL = tempDir.appendingPathComponent("compact.csb")
        let zipURL = tempDir.appendingPathComponent("legacy.clipbackup")
        try service.exportCompactBackup(to: compactURL, items: items)
        try service.exportBackup(to: zipURL, items: items)
        let compactSize = try Data(contentsOf: compactURL).count
        let zipSize = try Data(contentsOf: zipURL).count
        XCTAssertLessThan(compactSize, zipSize)
    }

    func testLegacyZipStillImports() throws {
        let items = makeItems()
        let zipURL = tempDir.appendingPathComponent("legacy.clipbackup")
        try service.exportBackup(to: zipURL, items: items)
        XCTAssertFalse(CompactBackupCodec.isCompactBackup(zipURL))
        let imported = try service.importBackup(from: zipURL, existingItems: [], mode: .replace)
        XCTAssertEqual(imported.count, items.filter { !$0.isSensitive }.count)
    }

    func testCorruptedCompactThrows() throws {
        let items = makeItems()
        let url = tempDir.appendingPathComponent("bad.csb")
        try service.exportCompactBackup(to: url, items: items)
        var data = try Data(contentsOf: url)
        data.removeLast(8)
        let badURL = tempDir.appendingPathComponent("bad2.csb")
        try data.write(to: badURL)
        XCTAssertThrowsError(try service.importBackup(from: badURL, existingItems: [], mode: .replace))
    }

    func testForeignFileRejectedAsCompact() throws {
        let url = tempDir.appendingPathComponent("foreign.csb")
        try Data("not a backup at all".utf8).write(to: url)
        XCTAssertFalse(CompactBackupCodec.isCompactBackup(url))
    }

    func testSizeComparisonReport() throws {
        let uniqueItems = (0..<2_000).map { i in
            ClipboardItem(content: "history entry \(i): the quick brown fox jumps over the lazy dog, copied from Safari", type: .text, sourceAppName: "Safari")
        }
        let repetitiveItems = (0..<2_000).map { i in
            ClipboardItem(content: "same copied line repeated across history \(i % 20)", type: .text, sourceAppName: "Safari")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let uniqueCompact = tempDir.appendingPathComponent("unique.csb")
        let uniqueZip = tempDir.appendingPathComponent("unique.clipbackup")
        try service.exportCompactBackup(to: uniqueCompact, items: uniqueItems)
        try service.exportBackup(to: uniqueZip, items: uniqueItems)
        let uniqueRaw = try encoder.encode(uniqueItems).count
        let uniqueCompactSize = try Data(contentsOf: uniqueCompact).count
        let uniqueZipSize = try Data(contentsOf: uniqueZip).count

        let repCompact = tempDir.appendingPathComponent("rep.csb")
        try service.exportCompactBackup(to: repCompact, items: repetitiveItems)
        let repRaw = try encoder.encode(repetitiveItems).count
        let repCompactSize = try Data(contentsOf: repCompact).count

        print("SIZE_REPORT uniqueRaw=\(uniqueRaw) uniqueZip=\(uniqueZipSize) uniqueCompact=\(uniqueCompactSize) repRaw=\(repRaw) repCompact=\(repCompactSize)")
        XCTAssertLessThan(uniqueCompactSize, uniqueRaw / 5)
        XCTAssertLessThan(uniqueCompactSize, uniqueZipSize)
        XCTAssertLessThan(repCompactSize, repRaw / 10)
    }

    func testMergeDeduplicatesByText() throws {
        let items = Array(makeItems().prefix(5))
        let url = tempDir.appendingPathComponent("merge.csb")
        try service.exportCompactBackup(to: url, items: items)
        let imported = try service.importBackup(from: url, existingItems: items, mode: .merge)
        XCTAssertEqual(imported.count, items.count)
    }
}