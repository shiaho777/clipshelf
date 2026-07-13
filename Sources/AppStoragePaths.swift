import Foundation

enum AppStoragePaths {
    static let productDirectoryName = "ClipShelf"
    static let legacyDirectoryName = "ClipboardManager"

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
        migrateLegacyDirectoryIfNeeded(to: destination, fileManager: fileManager)
        return destination
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
