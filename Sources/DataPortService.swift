import Foundation
import os

#if canImport(SQLite3)
import SQLite3
#endif

enum DataPortError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .importFailed(let msg): return "Import failed: \(msg)"
        case .invalidArchive: return "Invalid backup archive"
        }
    }
}

enum ImportMode {
    case merge
    case replace
}

final class DataPortService {
    private let storageDirectory: URL
    private let historyStore: ClipboardHistoryStore
    private let imageStore: ClipboardImageStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "DataPort")

    init(storageDirectory: URL, historyStore: ClipboardHistoryStore, imageStore: ClipboardImageStore) {
        self.storageDirectory = storageDirectory
        self.historyStore = historyStore
        self.imageStore = imageStore
    }

    // MARK: - Export

    func exportBackup(to destinationURL: URL, items: [ClipboardItem]) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clipbackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write history JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let historyData = try encoder.encode(items)
        try historyData.write(to: tempDir.appendingPathComponent("history.json"))

        // Copy image files
        let imagesDir = tempDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        for item in items {
            guard let fileName = item.imageFileName else { continue }
            if let data = imageStore.imageData(for: fileName) {
                try data.write(to: imagesDir.appendingPathComponent(fileName))
            }
        }

        // Create zip archive
        let zipTask = Process()
        zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipTask.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, destinationURL.path]
        try zipTask.run()
        zipTask.waitUntilExit()
        guard zipTask.terminationStatus == 0 else {
            throw DataPortError.exportFailed("ditto exited with status \(zipTask.terminationStatus)")
        }
    }

    // MARK: - Import

    func importBackup(from sourceURL: URL, existingItems: [ClipboardItem], mode: ImportMode) throws -> [ClipboardItem] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clipimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Extract zip
        let unzipTask = Process()
        unzipTask.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipTask.arguments = ["-x", "-k", sourceURL.path, tempDir.path]
        try unzipTask.run()
        unzipTask.waitUntilExit()
        guard unzipTask.terminationStatus == 0 else {
            throw DataPortError.importFailed("ditto exited with status \(unzipTask.terminationStatus)")
        }

        // Find history.json (may be nested in a subdirectory)
        let historyURL = try findFile(named: "history.json", in: tempDir)
        guard let historyURL else {
            throw DataPortError.invalidArchive
        }

        let historyData = try Data(contentsOf: historyURL)
        let importedItems = try JSONDecoder().decode([ClipboardItem].self, from: historyData)

        // Copy images into image store
        let imagesDir = historyURL.deletingLastPathComponent().appendingPathComponent("images")
        if FileManager.default.fileExists(atPath: imagesDir.path) {
            if let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
                for file in files {
                    let data = try Data(contentsOf: file)
                    try imageStore.saveImageData(data, fileName: file.lastPathComponent)
                }
            }
        }

        switch mode {
        case .replace:
            return importedItems
        case .merge:
            return mergeItems(existing: existingItems, imported: importedItems)
        }
    }

    // MARK: - Helpers

    private func mergeItems(existing: [ClipboardItem], imported: [ClipboardItem]) -> [ClipboardItem] {
        var existingContentSet = Set(existing.filter { $0.type != .image }.map(\.content))
        var existingHashSet = Set(existing.compactMap(\.imageHash))
        var merged = existing

        for item in imported {
            if item.type == .image {
                guard let hash = item.imageHash, !existingHashSet.contains(hash) else { continue }
                existingHashSet.insert(hash)
                merged.append(item)
            } else {
                guard !existingContentSet.contains(item.content) else { continue }
                existingContentSet.insert(item.content)
                merged.append(item)
            }
        }

        return merged.sorted { $0.timestamp > $1.timestamp }
    }

    private func findFile(named name: String, in directory: URL) throws -> URL? {
        let directFile = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: directFile.path) { return directFile }

        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == name { return fileURL }
            }
        }
        return nil
    }

    // MARK: - CSV Export

    /// Export clipboard history as a UTF-8 CSV file.
    /// Columns: timestamp, type, content, source_app, is_pinned, ocr_text
    func exportCSV(to url: URL, items: [ClipboardItem]) throws {
        let df = ISO8601DateFormatter()
        var lines: [String] = ["timestamp,type,content,source_app,is_pinned,ocr_text"]
        for item in items {
            let ts   = df.string(from: item.timestamp)
            let type = item.type.rawValue
            let content = item.content.csvEscaped
            let app  = (item.sourceAppName ?? "").csvEscaped
            let pin  = item.isPinned ? "1" : "0"
            let ocr  = (item.ocrText ?? "").csvEscaped
            lines.append("\(ts),\(type),\(content),\(app),\(pin),\(ocr)")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Markdown Export

    /// Export clipboard history as a Markdown table.
    func exportMarkdown(to url: URL, items: [ClipboardItem]) throws {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        var lines: [String] = [
            "# Clipboard History",
            "",
            "| # | Time | Type | Content | App | Pinned |",
            "|---|------|------|---------|-----|--------|"
        ]
        for (i, item) in items.enumerated() {
            let ts      = df.string(from: item.timestamp)
            let type    = item.type.rawValue
            let content = String(item.content.prefix(100))
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "|", with: "\\|")
            let app    = item.sourceAppName ?? "-"
            let pinned = item.isPinned ? "📌" : ""
            lines.append("| \(i + 1) | \(ts) | \(type) | \(content) | \(app) | \(pinned) |")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Maccy Import

    /// Import text items from Maccy's CoreData-backed SQLite database.
    /// Typical location: ~/Library/Containers/org.p0deje.Maccy/Data/Library/
    ///                   Application Support/Maccy/Storage.sqlite
    func importMaccy(from dbURL: URL, existingItems: [ClipboardItem], mode: ImportMode) throws -> [ClipboardItem] {
#if canImport(SQLite3)
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            throw DataPortError.importFailed("Cannot open database at \(dbURL.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        // Verify the Maccy CoreData schema
        var chk: OpaquePointer?
        let hasTable = sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='ZHISTORYITEM'", -1, &chk, nil) == SQLITE_OK
            && sqlite3_step(chk) == SQLITE_ROW
        sqlite3_finalize(chk)
        guard hasTable else {
            throw DataPortError.importFailed("Not a Maccy database: ZHISTORYITEM table not found")
        }

        var stmt: OpaquePointer?
        let sql = "SELECT ZTITLE, ZFIRSTCOPIEDAT, ZNUMBEROFCOPIES, ZPINNED FROM ZHISTORYITEM WHERE ZTITLE IS NOT NULL AND ZTITLE != '' ORDER BY ZLASTCOPIEDAT DESC LIMIT 2000"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DataPortError.importFailed("Failed to query Maccy items")
        }
        defer { sqlite3_finalize(stmt) }

        var imported: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let title = String(cString: cStr)
            guard !title.isEmpty else { continue }
            // CoreData stores dates as NSTimeInterval since 2001-01-01 (same as Swift Date reference date)
            let rawDate = sqlite3_column_double(stmt, 1)
            let timestamp = rawDate > 0 ? Date(timeIntervalSinceReferenceDate: rawDate) : Date()
            let useCount  = max(0, Int(sqlite3_column_int(stmt, 2)))
            let isPinned  = sqlite3_column_int(stmt, 3) != 0
            imported.append(ClipboardItem(content: title, type: .text,
                                          timestamp: timestamp, isPinned: isPinned, useCount: useCount))
        }
        guard !imported.isEmpty else {
            throw DataPortError.importFailed("No text items found in Maccy database")
        }
        return mode == .replace ? imported : mergeItems(existing: existingItems, imported: imported)
#else
        throw DataPortError.importFailed("SQLite3 not available on this platform")
#endif
    }

    // MARK: - Alfred Import

    /// Import text items from Alfred's clipboard SQLite database.
    /// Typical location: ~/Library/Application Support/Alfred/Databases/clipboard.alfdb
    func importAlfred(from dbURL: URL, existingItems: [ClipboardItem], mode: ImportMode) throws -> [ClipboardItem] {
#if canImport(SQLite3)
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            throw DataPortError.importFailed("Cannot open Alfred database at \(dbURL.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        var chk: OpaquePointer?
        let hasTable = sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard'", -1, &chk, nil) == SQLITE_OK
            && sqlite3_step(chk) == SQLITE_ROW
        sqlite3_finalize(chk)
        guard hasTable else {
            throw DataPortError.importFailed("Not an Alfred clipboard database: 'clipboard' table not found")
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT item, ts, app FROM clipboard WHERE item IS NOT NULL ORDER BY ts DESC LIMIT 2000", -1, &stmt, nil) == SQLITE_OK else {
            throw DataPortError.importFailed("Failed to query Alfred items")
        }
        defer { sqlite3_finalize(stmt) }

        var imported: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let content = String(cString: cStr)
            guard !content.isEmpty else { continue }
            let ts = sqlite3_column_int64(stmt, 1)
            let timestamp = ts > 0 ? Date(timeIntervalSince1970: Double(ts)) : Date()
            let appName: String? = {
                guard let c = sqlite3_column_text(stmt, 2) else { return nil }
                let s = String(cString: c); return s.isEmpty ? nil : s
            }()
            imported.append(ClipboardItem(content: content, type: .text,
                                          timestamp: timestamp, sourceAppName: appName))
        }
        guard !imported.isEmpty else {
            throw DataPortError.importFailed("No items found in Alfred database")
        }
        return mode == .replace ? imported : mergeItems(existing: existingItems, imported: imported)
#else
        throw DataPortError.importFailed("SQLite3 not available on this platform")
#endif
    }
}

// MARK: - CSV escape helper

private extension String {
    /// Wraps the string in double-quotes and escapes internal quotes if needed for CSV.
    var csvEscaped: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return self
    }
}
