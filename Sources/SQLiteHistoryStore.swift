import Foundation
import os

#if canImport(SQLite3)
import SQLite3
#endif

/// The `SQLITE_TRANSIENT` destructor type tells SQLite to make its own copy of
/// bound data immediately. Defined as `((sqlite3_destructor_type)(−1))` in C;
/// Swift lacks the macro so we replicate it via `unsafeBitCast`.
private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteHistoryStore: ClipboardHistoryStore {
    private var db: OpaquePointer?
    /// Protects `lastKnownItems` and `lastKnownOrder` against concurrent access from
    /// the persistence queue (saveItems) and any other queue that calls loadItems.
    private let itemsLock = NSLock()
    private let dbLock = NSRecursiveLock()
    private var lastKnownItems: [UUID: ClipboardItem] = [:]
    private var lastKnownOrder: [UUID] = []
    private let dbURL: URL
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "SQLiteStore")

    /// Each migration is a (targetVersion, sql) pair. Migrations run in order.
    /// Version 0 = fresh database before any migration.
    /// Version 1 = initial schema (clipboard_items table).
    /// Add new migrations here for future schema changes.
    static let migrations: [(version: Int, sql: String)] = [
        // Version 1: initial schema
        (1, """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL DEFAULT '',
            rtf_data BLOB,
            type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            use_count INTEGER NOT NULL DEFAULT 0,
            image_hash TEXT,
            image_file_name TEXT,
            ocr_text TEXT,
            source_bundle_id TEXT,
            source_app_name TEXT,
            is_sensitive INTEGER NOT NULL DEFAULT 0,
            expires_at REAL
        )
        """),
        // Version 2: FTS5 full-text index for content, ocr_text, source_app_name.
        // Triggers keep the FTS table in sync with the main table automatically.
        // The final INSERT … SELECT populates FTS from existing rows on upgrade.
        (2, """
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts
        USING fts5(
            content, ocr_text, source_app_name,
            content='clipboard_items',
            content_rowid='rowid'
        );
        CREATE TRIGGER IF NOT EXISTS clipboard_items_ai
        AFTER INSERT ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(rowid, content, ocr_text, source_app_name)
            VALUES (
                new.rowid,
                new.content,
                coalesce(new.ocr_text, ''),
                coalesce(new.source_app_name, '')
            );
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_items_ad
        AFTER DELETE ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, content, ocr_text, source_app_name)
            VALUES (
                'delete',
                old.rowid,
                old.content,
                coalesce(old.ocr_text, ''),
                coalesce(old.source_app_name, '')
            );
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_items_au
        AFTER UPDATE ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, content, ocr_text, source_app_name)
            VALUES (
                'delete',
                old.rowid,
                old.content,
                coalesce(old.ocr_text, ''),
                coalesce(old.source_app_name, '')
            );
            INSERT INTO clipboard_fts(rowid, content, ocr_text, source_app_name)
            VALUES (
                new.rowid,
                new.content,
                coalesce(new.ocr_text, ''),
                coalesce(new.source_app_name, '')
            );
        END;
        INSERT INTO clipboard_fts(rowid, content, ocr_text, source_app_name)
            SELECT rowid, content, coalesce(ocr_text, ''), coalesce(source_app_name, '')
            FROM clipboard_items;
        """),
        // Version 3: AES-256-GCM encryption columns for sensitive items + NLEmbedding vector storage.
        // content_enc / rtf_enc hold AES-GCM combined ciphertext; is_enc flags whether
        // the plaintext columns carry a placeholder instead of real data.
        (3, """
        ALTER TABLE clipboard_items ADD COLUMN content_enc BLOB;
        ALTER TABLE clipboard_items ADD COLUMN rtf_enc BLOB;
        ALTER TABLE clipboard_items ADD COLUMN is_enc INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE clipboard_items ADD COLUMN embedding BLOB;
        """),
        // Version 4: Rebuild FTS5 index with the trigram tokenizer.
        // The trigram tokenizer splits text into overlapping 3-character windows,
        // enabling substring search for CJK and all other scripts without word boundaries.
        // We drop the old table + triggers and recreate them, then issue a single
        // `VALUES('rebuild')` command which SQLite handles as an efficient full re-index.
        (4, """
        DROP TABLE IF EXISTS clipboard_fts;
        DROP TRIGGER IF EXISTS clipboard_items_ai;
        DROP TRIGGER IF EXISTS clipboard_items_ad;
        DROP TRIGGER IF EXISTS clipboard_items_au;
        CREATE VIRTUAL TABLE clipboard_fts
        USING fts5(
            content, ocr_text, source_app_name,
            content='clipboard_items',
            content_rowid='rowid',
            tokenize='trigram'
        );
        CREATE TRIGGER clipboard_items_ai
        AFTER INSERT ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(rowid, content, ocr_text, source_app_name)
            VALUES (new.rowid, new.content, coalesce(new.ocr_text,''), coalesce(new.source_app_name,''));
        END;
        CREATE TRIGGER clipboard_items_ad
        AFTER DELETE ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, content, ocr_text, source_app_name)
            VALUES ('delete', old.rowid, old.content, coalesce(old.ocr_text,''), coalesce(old.source_app_name,''));
        END;
        CREATE TRIGGER clipboard_items_au
        AFTER UPDATE ON clipboard_items BEGIN
            INSERT INTO clipboard_fts(clipboard_fts, rowid, content, ocr_text, source_app_name)
            VALUES ('delete', old.rowid, old.content, coalesce(old.ocr_text,''), coalesce(old.source_app_name,''));
            INSERT INTO clipboard_fts(rowid, content, ocr_text, source_app_name)
            VALUES (new.rowid, new.content, coalesce(new.ocr_text,''), coalesce(new.source_app_name,''));
        END;
        INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild');
        """),
        (5, """
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_order
        ON clipboard_items(is_pinned DESC, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_embedding_order
        ON clipboard_items(is_pinned DESC, timestamp DESC)
        WHERE embedding IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_expires
        ON clipboard_items(expires_at)
        WHERE expires_at IS NOT NULL;
        """)
    ]

    static var currentSchemaVersion: Int {
        migrations.last?.version ?? 0
    }

    init(storageDirectory: URL) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        self.dbURL = storageDirectory.appendingPathComponent("history.db")
        openDatabase()
        runMigrations()
        // PRAGMA optimize is intentionally called at shutdown (optimizeForClose()),
        // not here. Calling it at open provides no benefit as query statistics are empty.
    }

    /// Call just before closing the database (e.g. applicationWillTerminate).
    /// Updates SQLite query-planner statistics for better next-open performance.
    func optimizeForClose() {
        withDatabaseLock {
            exec("PRAGMA optimize")
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - ClipboardHistoryStore

    /// Full-text search via FTS5. Returns matching item IDs ordered by BM25 relevance
    /// (pinned items first). Falls back gracefully if FTS5 is unavailable.
    func searchFTS(_ query: String, limit: Int = 500) -> [UUID] {
        withDatabaseLock {
            searchFTSLocked(query, limit: limit)
        }
    }

    private func searchFTSLocked(_ query: String, limit: Int) -> [UUID] {
        guard let db else { return [] }
        let sanitized = sanitizeFTSQuery(query)
        let boundedLimit = max(0, min(limit, Int(Int32.max)))
        guard boundedLimit > 0 else { return [] }
        guard !sanitized.isEmpty else { return [] }

        let sql = """
        SELECT ci.id
        FROM clipboard_fts
        JOIN clipboard_items ci ON ci.rowid = clipboard_fts.rowid
        WHERE clipboard_fts MATCH ?
        ORDER BY ci.is_pinned DESC, bm25(clipboard_fts) ASC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return searchLikeLocked(tokens: sanitized.components(separatedBy: " "), limit: boundedLimit)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sanitized, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        sqlite3_bind_int(stmt, 2, Int32(boundedLimit))

        var uuids: [UUID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idStr = columnText(stmt!, 0), let uuid = UUID(uuidString: idStr) {
                uuids.append(uuid)
            }
        }
        if !uuids.isEmpty { return uuids }
        return searchLikeLocked(tokens: sanitized.components(separatedBy: " "), limit: boundedLimit)
    }

    private func searchLikeLocked(tokens: [String], limit: Int) -> [UUID] {
        guard let db else { return [] }
        let terms = tokens.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let boundedLimit = max(0, min(limit, Int(Int32.max)))
        guard boundedLimit > 0 else { return [] }

        let whereClause = terms.map { _ in "(content LIKE ? OR ocr_text LIKE ? OR source_app_name LIKE ?)" }.joined(separator: " AND ")
        let sql = """
        SELECT id
        FROM clipboard_items
        WHERE \(whereClause)
        ORDER BY is_pinned DESC, timestamp DESC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        for term in terms {
            let pattern = "%\(term)%"
            sqlite3_bind_text(stmt, bindIndex, pattern, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            sqlite3_bind_text(stmt, bindIndex + 1, pattern, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            sqlite3_bind_text(stmt, bindIndex + 2, pattern, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            bindIndex += 3
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(boundedLimit))

        var uuids: [UUID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idStr = columnText(stmt!, 0), let uuid = UUID(uuidString: idStr) {
                uuids.append(uuid)
            }
        }
        return uuids
    }

    /// Sanitise a raw user query into a safe FTS5 MATCH expression for the trigram tokenizer.
    /// The trigram tokenizer performs inherent substring matching, so:
    ///   - No `*` suffix is appended (that is a prefix-scan hint irrelevant to trigrams)
    ///   - Tokens shorter than 3 characters are dropped (trigrams need at least 3 chars)
    ///   - FTS5 meta-characters are stripped to prevent injection
    private func sanitizeFTSQuery(_ raw: String) -> String {
        var cleaned = raw
        for ch: Character in "\"*()^:-+" {
            cleaned = cleaned.replacingOccurrences(of: String(ch), with: " ")
        }
        let reserved: Set<String> = ["AND", "OR", "NOT"]
        let tokens = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { token in
                !token.isEmpty
                && !reserved.contains(token.uppercased())
                && token.count >= 3  // trigram minimum
            }
        guard !tokens.isEmpty else { return "" }
        // Join with implicit AND (all tokens must appear as trigrams in the row).
        return tokens.joined(separator: " ")
    }

    func loadItems() throws -> [ClipboardItem] {
        try loadItems(limit: nil)
    }

    func loadItems(limit: Int?) throws -> [ClipboardItem] {
        try withDatabaseLock {
            try loadItemsLocked(limit: limit)
        }
    }

    func itemCount() throws -> Int {
        try withDatabaseLock {
            itemCountLocked()
        }
    }

    func loadItem(id: UUID) throws -> ClipboardItem? {
        try withDatabaseLock {
            try loadItemLocked(id: id)
        }
    }

    private func loadItemsLocked(limit: Int?) throws -> [ClipboardItem] {
        guard let db else { throw StoreError.databaseNotOpen }

        let selectCols = "id, content, rtf_data, type, timestamp, is_pinned, use_count, image_hash, image_file_name, ocr_text, source_bundle_id, source_app_name, is_sensitive, expires_at, content_enc, rtf_enc, is_enc"

        func fetch(_ sql: String) throws -> [ClipboardItem] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            var rows: [ClipboardItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = readRow(stmt!) {
                    rows.append(item)
                }
            }
            return rows
        }

        let items: [ClipboardItem]
        if let limit, limit >= 0 {
            let pinned = try fetch("SELECT \(selectCols) FROM clipboard_items WHERE is_pinned = 1 ORDER BY timestamp DESC")
            let remaining = max(0, limit - pinned.count)
            let unpinned: [ClipboardItem]
            if remaining > 0 {
                unpinned = try fetch("SELECT \(selectCols) FROM clipboard_items WHERE is_pinned = 0 ORDER BY timestamp DESC LIMIT \(remaining)")
            } else {
                unpinned = []
            }
            items = pinned + unpinned
        } else {
            items = try fetch("SELECT \(selectCols) FROM clipboard_items ORDER BY is_pinned DESC, timestamp DESC")
        }

        itemsLock.withLock {
            for item in items {
                lastKnownItems[item.id] = item
            }
            if limit == nil {
                lastKnownOrder = items.map(\.id)
            } else {
                let loadedIDs = items.map(\.id)
                var merged = loadedIDs
                for id in lastKnownOrder where !loadedIDs.contains(id) {
                    merged.append(id)
                }
                lastKnownOrder = merged
            }
        }
        return items
    }


    private func loadItemLocked(id: UUID) throws -> ClipboardItem? {
        guard let db else { throw StoreError.databaseNotOpen }
        if let cached = itemsLock.withLock({ lastKnownItems[id] }) {
            return cached
        }
        let sql = "SELECT id, content, rtf_data, type, timestamp, is_pinned, use_count, image_hash, image_file_name, ocr_text, source_bundle_id, source_app_name, is_sensitive, expires_at, content_enc, rtf_enc, is_enc FROM clipboard_items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let idString = id.uuidString
        sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let item = readRow(stmt!) else { return nil }
        itemsLock.withLock {
            lastKnownItems[item.id] = item
        }
        return item
    }

    @discardableResult
    func saveItems(_ items: [ClipboardItem]) throws -> Bool {
        try withDatabaseLock {
            try saveItemsLocked(items)
        }
    }

    private func saveItemsLocked(_ items: [ClipboardItem]) throws -> Bool {
        guard let db else { throw StoreError.databaseNotOpen }

        let newMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let newIDs = Set(newMap.keys)
        let currentItems = itemsLock.withLock { lastKnownItems }

        let toInsert = newIDs.subtracting(currentItems.keys)
        let toUpdate = newIDs.intersection(currentItems.keys).filter { newMap[$0] != currentItems[$0] }

        guard !toInsert.isEmpty || !toUpdate.isEmpty else {
            return false
        }

        exec("BEGIN")
        var anyFailed = false

        if !toUpdate.isEmpty && !deleteItemsPrepared(toUpdate) {
            anyFailed = true
        }

        let insertItems = toInsert.compactMap { newMap[$0] }
        if !insertItems.isEmpty && !insertItemsPrepared(insertItems) {
            anyFailed = true
        }

        let updateItems = toUpdate.compactMap { newMap[$0] }
        if !updateItems.isEmpty && !insertItemsPrepared(updateItems) {
            anyFailed = true
        }

        if anyFailed {
            exec("ROLLBACK")
            logger.error("saveItems: one or more writes failed — transaction rolled back; will retry on next save")
            return false
        }

        exec("COMMIT")
        itemsLock.withLock {
            for (id, item) in newMap {
                lastKnownItems[id] = item
            }
            var order = items.map(\.id)
            for id in lastKnownOrder where !newIDs.contains(id) {
                order.append(id)
            }
            lastKnownOrder = order
        }
        return true
    }

    @discardableResult
    func trimUnpinned(to maxUnpinned: Int) throws -> Set<UUID> {
        try withDatabaseLock {
            try trimUnpinnedLocked(to: maxUnpinned)
        }
    }

    private func trimUnpinnedLocked(to maxUnpinned: Int) throws -> Set<UUID> {
        guard let db else { throw StoreError.databaseNotOpen }
        let bounded = max(0, maxUnpinned)
        let sql = """
        SELECT id FROM clipboard_items
        WHERE is_pinned = 0
        ORDER BY timestamp DESC
        LIMIT -1 OFFSET \(bounded)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var ids = Set<UUID>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                let idString = String(cString: cString)
                if let id = UUID(uuidString: idString) {
                    ids.insert(id)
                }
            }
        }
        guard !ids.isEmpty else { return [] }
        _ = try deleteItemsLocked(ids: ids)
        return ids
    }

    @discardableResult
    func deleteUnpinned() throws -> Set<UUID> {
        try withDatabaseLock {
            try deleteUnpinnedLocked()
        }
    }

    private func deleteUnpinnedLocked() throws -> Set<UUID> {
        guard db != nil else { throw StoreError.databaseNotOpen }
        let sql = "SELECT id FROM clipboard_items WHERE is_pinned = 0"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var ids = Set<UUID>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                let idString = String(cString: cString)
                if let id = UUID(uuidString: idString) {
                    ids.insert(id)
                }
            }
        }
        guard !ids.isEmpty else { return [] }
        _ = try deleteItemsLocked(ids: ids)
        return ids
    }

    @discardableResult
    func deleteExpired(before date: Date) throws -> Set<UUID> {
        try withDatabaseLock {
            try deleteExpiredLocked(before: date)
        }
    }

    private func deleteExpiredLocked(before date: Date) throws -> Set<UUID> {
        guard db != nil else { throw StoreError.databaseNotOpen }
        let sql = "SELECT id FROM clipboard_items WHERE expires_at IS NOT NULL AND expires_at <= ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSinceReferenceDate)
        var ids = Set<UUID>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                let idString = String(cString: cString)
                if let id = UUID(uuidString: idString) {
                    ids.insert(id)
                }
            }
        }
        guard !ids.isEmpty else { return [] }
        _ = try deleteItemsLocked(ids: ids)
        return ids
    }

    @discardableResult
    func deleteUnpinnedOlderThan(_ date: Date) throws -> Set<UUID> {
        try withDatabaseLock {
            try deleteUnpinnedOlderThanLocked(date)
        }
    }

    private func deleteUnpinnedOlderThanLocked(_ date: Date) throws -> Set<UUID> {
        guard db != nil else { throw StoreError.databaseNotOpen }
        let sql = "SELECT id FROM clipboard_items WHERE is_pinned = 0 AND timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSinceReferenceDate)
        var ids = Set<UUID>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                let idString = String(cString: cString)
                if let id = UUID(uuidString: idString) {
                    ids.insert(id)
                }
            }
        }
        guard !ids.isEmpty else { return [] }
        _ = try deleteItemsLocked(ids: ids)
        return ids
    }

    @discardableResult
    func upsertItem(_ item: ClipboardItem) throws -> Bool {
        try withDatabaseLock {
            try upsertItemLocked(item)
        }
    }

    private func upsertItemLocked(_ item: ClipboardItem) throws -> Bool {
        guard db != nil else { throw StoreError.databaseNotOpen }

        let current = itemsLock.withLock { lastKnownItems[item.id] }
        guard current != item else { return false }

        exec("BEGIN")
        let ok = insertItem(item)

        if ok {
            exec("COMMIT")
            itemsLock.withLock {
                lastKnownItems[item.id] = item
                if current == nil {
                    lastKnownOrder.insert(item.id, at: 0)
                }
            }
            return true
        }

        exec("ROLLBACK")
        logger.error("upsertItem failed; transaction rolled back")
        return false
    }

    @discardableResult
    func deleteItems(ids: Set<UUID>) throws -> Bool {
        try withDatabaseLock {
            try deleteItemsLocked(ids: ids)
        }
    }

    private func deleteItemsLocked(ids: Set<UUID>) throws -> Bool {
        guard db != nil else { throw StoreError.databaseNotOpen }
        guard !ids.isEmpty else { return false }

        let existingIDs = itemsLock.withLock { ids.intersection(lastKnownItems.keys) }
        guard !existingIDs.isEmpty else { return false }

        exec("BEGIN")
        let anyFailed = !deleteItemsPrepared(existingIDs)

        if anyFailed {
            exec("ROLLBACK")
            logger.error("deleteItems failed; transaction rolled back")
            return false
        }

        exec("COMMIT")
        itemsLock.withLock {
            for id in existingIDs {
                lastKnownItems.removeValue(forKey: id)
            }
            lastKnownOrder.removeAll { existingIDs.contains($0) }
        }
        return true
    }

    @discardableResult
    func updateUseCount(id: UUID, useCount: Int) throws -> Bool {
        try withDatabaseLock {
            try updateUseCountLocked(id: id, useCount: useCount)
        }
    }

    @discardableResult
    func updateUseCounts(_ useCountsByID: [UUID: Int]) throws -> Bool {
        try withDatabaseLock {
            try updateUseCountsLocked(useCountsByID)
        }
    }

    private func updateUseCountsLocked(_ useCountsByID: [UUID: Int]) throws -> Bool {
        guard db != nil else { throw StoreError.databaseNotOpen }
        guard !useCountsByID.isEmpty else { return false }

        let currentItems = itemsLock.withLock { lastKnownItems }
        let changes = useCountsByID.compactMap { id, useCount -> (UUID, Int, ClipboardItem)? in
            guard var item = currentItems[id], item.useCount != useCount else { return nil }
            item.useCount = useCount
            return (id, useCount, item)
        }
        guard !changes.isEmpty else { return false }

        exec("BEGIN")
        var anyFailed = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE clipboard_items SET use_count = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            for (id, useCount, _) in changes {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int(stmt, 1, Int32(useCount))
                sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    anyFailed = true
                    break
                }
            }
        } else {
            anyFailed = true
        }
        if anyFailed {
            exec("ROLLBACK")
            logger.error("updateUseCounts failed")
            return false
        }
        exec("COMMIT")

        itemsLock.withLock {
            for (id, _, item) in changes {
                lastKnownItems[id] = item
            }
        }
        return true
    }

    private func updateUseCountLocked(id: UUID, useCount: Int) throws -> Bool {
        guard db != nil else { throw StoreError.databaseNotOpen }

        let current = itemsLock.withLock { lastKnownItems[id] }
        guard var item = current, item.useCount != useCount else { return false }

        let ok = execBind("UPDATE clipboard_items SET use_count = ? WHERE id = ?", bind: { stmt in
            sqlite3_bind_int(stmt, 1, Int32(useCount))
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        })
        guard ok else {
            logger.error("updateUseCount failed")
            return false
        }

        item.useCount = useCount
        itemsLock.withLock {
            lastKnownItems[id] = item
        }
        return true
    }

    // MARK: - Migration

    /// Migrate from JSON history file. Returns true if migration occurred.
    @discardableResult
    func migrateFromJSON(storageDirectory: URL) -> Bool {
        withDatabaseLock {
            migrateFromJSONLocked(storageDirectory: storageDirectory)
        }
    }

    private func migrateFromJSONLocked(storageDirectory: URL) -> Bool {
        let jsonURL = storageDirectory.appendingPathComponent("history.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: jsonURL.path) else { return false }

        do {
            let data = try Data(contentsOf: jsonURL)
            let items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            guard !items.isEmpty else {
                try fm.moveItem(at: jsonURL, to: jsonURL.appendingPathExtension("migrated"))
                return true
            }

            exec("BEGIN TRANSACTION")
            guard insertItemsPrepared(items) else {
                exec("ROLLBACK")
                return false
            }
            exec("COMMIT")

            lastKnownItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            lastKnownOrder = items.map(\.id)

            // Rename original file
            let migratedURL = jsonURL.appendingPathExtension("migrated")
            try? fm.removeItem(at: migratedURL)
            try fm.moveItem(at: jsonURL, to: migratedURL)
            logger.info("Migrated \(items.count) items from JSON to SQLite")
            return true
        } catch {
            logger.error("JSON migration failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func openDatabase() {
        let status = sqlite3_open(dbURL.path, &db)
        if status != SQLITE_OK {
            logger.error("Failed to open SQLite database: \(status)")
            db = nil
        } else {
            exec("PRAGMA journal_mode=WAL")
            exec("PRAGMA synchronous=NORMAL")
        }
    }

    // MARK: - Schema Migration

    private func getUserVersion() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func setUserVersion(_ version: Int) {
        exec("PRAGMA user_version = \(version)")
    }

    private func runMigrations() {
        guard db != nil else { return }
        let currentVersion = getUserVersion()
        let pendingMigrations = Self.migrations.filter { $0.version > currentVersion }
        guard !pendingMigrations.isEmpty else { return }

        // Run each migration in its own transaction so a failure can be precisely
        // rolled back without corrupting prior successful migrations.
        for migration in pendingMigrations {
            logger.info("Running schema migration to version \(migration.version)")
            exec("BEGIN")
            if exec(migration.sql) {
                setUserVersion(migration.version)
                exec("COMMIT")
                logger.info("Migration v\(migration.version) committed")
            } else {
                exec("ROLLBACK")
                logger.error("Migration v\(migration.version) failed — rolled back; stopping further migrations")
                break  // Leave the database at the last successfully committed version.
            }
        }
        logger.info("Database at schema version \(self.getUserVersion())")
    }

    @discardableResult
    private func insertItem(_ item: ClipboardItem) -> Bool {
        insertItemsPrepared([item])
    }

    private func insertItemsPrepared(_ items: [ClipboardItem]) -> Bool {
        guard let db else { return false }
        let sql = """
        INSERT OR REPLACE INTO clipboard_items
        (id, content, rtf_data, type, timestamp, is_pinned, use_count, image_hash, image_file_name, ocr_text, source_bundle_id, source_app_name, is_sensitive, expires_at, content_enc, rtf_enc, is_enc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("SQL prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for item in items {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bindItem(item, to: stmt!)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("SQL step failed: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
        }
        return true
    }

    private func deleteItemsPrepared(_ ids: Set<UUID>) -> Bool {
        guard let db else { return false }
        guard !ids.isEmpty else { return true }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else {
            logger.error("SQL prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for id in ids {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("SQL step failed: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
        }
        return true
    }

    private func bindItem(_ item: ClipboardItem, to stmt: OpaquePointer) {
        var storedContent = item.content
        var contentEncData: Data?
        var rtfEncData: Data?
        let isEnc: Bool
        if item.isSensitive, let contentData = item.content.data(using: .utf8) {
            storedContent = "[\u{1F512} Sensitive]"
            contentEncData = try? EncryptionService.shared.encrypt(contentData)
            if let rtf = item.rtfData { rtfEncData = try? EncryptionService.shared.encrypt(rtf) }
            isEnc = true
        } else {
            isEnc = false
        }

        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        sqlite3_bind_text(stmt, 2, storedContent, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        let rtfForColumn = isEnc ? nil : item.rtfData
        if let rtf = rtfForColumn {
            rtf.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT_DESTRUCTOR) }
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, item.type.rawValue, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        sqlite3_bind_double(stmt, 5, item.timestamp.timeIntervalSinceReferenceDate)
        sqlite3_bind_int(stmt, 6, item.isPinned ? 1 : 0)
        sqlite3_bind_int(stmt, 7, Int32(item.useCount))
        bindOptionalText(stmt, 8, item.imageHash)
        bindOptionalText(stmt, 9, item.imageFileName)
        bindOptionalText(stmt, 10, item.ocrText)
        bindOptionalText(stmt, 11, item.sourceBundleID)
        bindOptionalText(stmt, 12, item.sourceAppName)
        sqlite3_bind_int(stmt, 13, item.isSensitive ? 1 : 0)
        if let expires = item.expiresAt {
            sqlite3_bind_double(stmt, 14, expires.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(stmt, 14)
        }
        if let enc = contentEncData {
            enc.withUnsafeBytes { sqlite3_bind_blob(stmt, 15, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT_DESTRUCTOR) }
        } else {
            sqlite3_bind_null(stmt, 15)
        }
        if let enc = rtfEncData {
            enc.withUnsafeBytes { sqlite3_bind_blob(stmt, 16, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT_DESTRUCTOR) }
        } else {
            sqlite3_bind_null(stmt, 16)
        }
        sqlite3_bind_int(stmt, 17, isEnc ? 1 : 0)
    }

    private func readRow(_ stmt: OpaquePointer) -> ClipboardItem? {
        guard let idStr = columnText(stmt, 0), let id = UUID(uuidString: idStr),
              let typeStr = columnText(stmt, 3), let type = ClipboardItem.ItemType(rawValue: typeStr)
        else { return nil }

        var content = columnText(stmt, 1) ?? ""
        var rtfData: Data?
        if let blob = sqlite3_column_blob(stmt, 2) {
            let len = sqlite3_column_bytes(stmt, 2)
            rtfData = Data(bytes: blob, count: Int(len))
        }
        // Decrypt sensitive items (columns 14=content_enc, 15=rtf_enc, 16=is_enc)
        let isEnc = sqlite3_column_int(stmt, 16) != 0
        if isEnc {
            if sqlite3_column_type(stmt, 14) != SQLITE_NULL,
               let blob = sqlite3_column_blob(stmt, 14) {
                let len = sqlite3_column_bytes(stmt, 14)
                let encData = Data(bytes: blob, count: Int(len))
                if let dec = try? EncryptionService.shared.decrypt(encData),
                   let str = String(data: dec, encoding: .utf8) {
                    content = str
                }
            }
            if sqlite3_column_type(stmt, 15) != SQLITE_NULL,
               let blob = sqlite3_column_blob(stmt, 15) {
                let len = sqlite3_column_bytes(stmt, 15)
                let encData = Data(bytes: blob, count: Int(len))
                rtfData = try? EncryptionService.shared.decrypt(encData)
            }
        }
        let timestamp = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 4))
        let isPinned = sqlite3_column_int(stmt, 5) != 0
        let useCount = Int(sqlite3_column_int(stmt, 6))
        let imageHash = columnText(stmt, 7)
        let imageFileName = columnText(stmt, 8)
        let ocrText = columnText(stmt, 9)
        let sourceBundleID = columnText(stmt, 10)
        let sourceAppName = columnText(stmt, 11)
        let isSensitive = sqlite3_column_int(stmt, 12) != 0
        var expiresAt: Date?
        if sqlite3_column_type(stmt, 13) != SQLITE_NULL {
            expiresAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 13))
        }

        return ClipboardItem(
            id: id, content: content, rtfData: rtfData, type: type,
            timestamp: timestamp, isPinned: isPinned, useCount: useCount,
            imageHash: imageHash, imageFileName: imageFileName, ocrText: ocrText,
            sourceBundleID: sourceBundleID, sourceAppName: sourceAppName,
            isSensitive: isSensitive, expiresAt: expiresAt
        )
    }

    private func itemCountLocked() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clipboard_items", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Embedding Storage

    /// Persist a Float32 embedding vector for a clipboard item.
    /// Called from SemanticSearchService's background queue after computation.
    func saveEmbedding(_ vector: [Float32], for id: UUID) {
        withDatabaseLock {
            let data = SemanticSearchService.shared.float32ArrayToData(vector)
            let sql = "UPDATE clipboard_items SET embedding = ? WHERE id = ?"
            execBind(sql) { stmt in
                data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT_DESTRUCTOR) }
                sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            }
        }
    }

    /// Load all persisted embedding vectors into memory. Called once at startup.
    func loadEmbeddings(limit: Int? = nil) -> [UUID: [Float32]] {
        withDatabaseLock {
            loadEmbeddingsLocked(limit: limit)
        }
    }

    private func loadEmbeddingsLocked(limit: Int?) -> [UUID: [Float32]] {
        guard let db else { return [:] }
        let sql: String
        if let limit {
            sql = "SELECT id, embedding FROM clipboard_items WHERE embedding IS NOT NULL ORDER BY is_pinned DESC, timestamp DESC LIMIT \(max(0, limit))"
        } else {
            sql = "SELECT id, embedding FROM clipboard_items WHERE embedding IS NOT NULL"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [UUID: [Float32]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt!, 0),
                  let uuid = UUID(uuidString: idStr),
                  let blob = sqlite3_column_blob(stmt!, 1) else { continue }
            let len = sqlite3_column_bytes(stmt!, 1)
            let data = Data(bytes: blob, count: Int(len))
            result[uuid] = SemanticSearchService.shared.dataToFloat32Array(data)
        }
        return result
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        let status = sqlite3_exec(db, sql, nil, nil, nil)
        if status != SQLITE_OK {
            logger.error("SQL exec failed (\(status)): \(String(cString: sqlite3_errmsg(self.db!)))")
            return false
        }
        return true
    }

    @discardableResult
    private func execBind(_ sql: String, bind: (OpaquePointer) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("SQL prepare failed: \(String(cString: sqlite3_errmsg(self.db!)))")
            return false
        }
        bind(stmt!)
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if !success {
            logger.error("SQL step failed: \(String(cString: sqlite3_errmsg(self.db!)))")
        }
        sqlite3_finalize(stmt)
        return success
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func withDatabaseLock<T>(_ work: () throws -> T) rethrows -> T {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try work()
    }

    enum StoreError: Error {
        case databaseNotOpen
        case queryFailed(String)
    }
}
