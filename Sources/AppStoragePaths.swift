import Foundation

enum AppStoragePaths {
    static let productDirectoryName = "ClipShelf"
    static let legacyDirectoryName = "ClipboardManager"

    /// The legacy-directory migration only ever needs to run once per process:
    /// afterwards the destination exists and repeated `defaultStorageDirectory()`
    /// calls (several per second on view-building paths) would otherwise hit the
    /// filesystem twice each. Reset only in tests via `resetMigrationMemoization()`.
    private nonisolated(unsafe) static var hasResolvedMigration = false
    private static let migrationMemoizationLock = NSLock()

    static func applicationSupportRoot(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static func defaultStorageDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let root = applicationSupportRoot(fileManager: fileManager)
        let destination = root.appendingPathComponent(productDirectoryName)
        if !migrationAlreadyResolved() {
            migrateLegacyDirectoryIfNeeded(to: destination, fileManager: fileManager)
            markMigrationResolved()
        }
        return destination
    }

    private static func migrationAlreadyResolved() -> Bool {
        migrationMemoizationLock.withLock { hasResolvedMigration }
    }

    private static func markMigrationResolved() {
        migrationMemoizationLock.withLock { hasResolvedMigration = true }
    }

    /// Test hook: clears the one-shot migration guard so migration behaviour
    /// can be exercised repeatedly within a single process.
    static func resetMigrationMemoization() {
        migrationMemoizationLock.withLock { hasResolvedMigration = false }
    }

    static func migrateLegacyDirectoryIfNeeded(
        to destination: URL,
        fileManager: FileManager = .default
    ) {
        let root = destination.deletingLastPathComponent()
        let legacy = root.appendingPathComponent(legacyDirectoryName)

        var isDestinationDir: ObjCBool = false
        let destinationExists = fileManager.fileExists(atPath: destination.path, isDirectory: &isDestinationDir) && isDestinationDir.boolValue

        var isLegacyDir: ObjCBool = false
        let legacyExists = fileManager.fileExists(atPath: legacy.path, isDirectory: &isLegacyDir) && isLegacyDir.boolValue

        guard legacyExists else { return }

        if !destinationExists {
            try? fileManager.moveItem(at: legacy, to: destination)
            return
        }

        guard let legacyItems = try? fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in legacyItems {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) { continue }
            try? fileManager.moveItem(at: item, to: target)
        }

        if let remaining = try? fileManager.contentsOfDirectory(atPath: legacy.path), remaining.isEmpty {
            try? fileManager.removeItem(at: legacy)
        }
    }
}
