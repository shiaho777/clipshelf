import XCTest
@testable import ClipShelf

final class AppStoragePathsTests: XCTestCase {
    func testMigratesLegacyDirectoryWhenDestinationMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfMigration-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent(AppStoragePaths.legacyDirectoryName, isDirectory: true)
        let destination = root.appendingPathComponent(AppStoragePaths.productDirectoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let marker = legacy.appendingPathComponent("history.sqlite")
        try Data("legacy".utf8).write(to: marker)

        AppStoragePaths.migrateLegacyDirectoryIfNeeded(to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("history.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testMergesMissingFilesWithoutOverwritingDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfMigration-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent(AppStoragePaths.legacyDirectoryName, isDirectory: true)
        let destination = root.appendingPathComponent(AppStoragePaths.productDirectoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try Data("keep".utf8).write(to: destination.appendingPathComponent("prefs.json"))
        try Data("old".utf8).write(to: legacy.appendingPathComponent("prefs.json"))
        try Data("snippets".utf8).write(to: legacy.appendingPathComponent("snippets.json"))

        AppStoragePaths.migrateLegacyDirectoryIfNeeded(to: destination)

        let prefs = try String(contentsOf: destination.appendingPathComponent("prefs.json"), encoding: .utf8)
        XCTAssertEqual(prefs, "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("snippets.json").path))
    }
}
