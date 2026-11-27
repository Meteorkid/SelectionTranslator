import Foundation
import SQLite3

enum HistoryStoreError: LocalizedError {
    case databaseUnavailable
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "历史数据库不可用"
        case .sqlite(let message):
            return "历史数据库错误：\(message)"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor HistoryStore {
    static let shared = HistoryStore()

    private var database: OpaquePointer?
    private var didCreateSchema = false
    private let databaseURL: URL

    init(databaseURL: URL? = nil) {
        let resolvedURL: URL
        if let databaseURL {
            resolvedURL = databaseURL
        } else {
            let directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SelectionTranslator", isDirectory: true)
            resolvedURL = directory.appendingPathComponent("history.sqlite3")
        }
        try? FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.databaseURL = resolvedURL

        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            resolvedURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return
        }
        database = handle
        sqlite3_busy_timeout(handle, 5_000)
        // Translation history is sensitive reading material. Restrict the
        // database to the current user until field-level encryption lands.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: resolvedURL.path
        )
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func insert(_ record: QueryRecord) throws -> Int64 {
        let db = try requireDatabase()
        let sql = """
        INSERT INTO queries
        (account_id, created_at, source_text, translated_text, context, app_name, bundle_id,
         source_kind, engine, target_language, is_favorite)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }

        try bind(record.accountID.uuidString, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, record.createdAt.timeIntervalSince1970)
        try bind(record.sourceText, to: statement, index: 3)
        try bind(record.translatedText, to: statement, index: 4)
        try bind(record.context, to: statement, index: 5)
        try bind(record.appName, to: statement, index: 6)
        try bind(record.bundleID ?? "", to: statement, index: 7)
        try bind(record.sourceKind, to: statement, index: 8)
        try bind(record.engine, to: statement, index: 9)
        try bind(record.targetLanguage, to: statement, index: 10)
        sqlite3_bind_int(statement, 11, record.isFavorite ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func records(
        accountID: UUID,
        search: String = "",
        favoritesOnly: Bool = false,
        limit: Int = 300
    ) throws -> [QueryRecord] {
        let db = try requireDatabase()
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let whereFavorite = favoritesOnly ? "AND is_favorite = 1" : ""
        let whereSearch = trimmedSearch.isEmpty
            ? ""
            : "AND (source_text LIKE ? OR translated_text LIKE ? OR context LIKE ? OR app_name LIKE ?)"
        let sql = """
        SELECT id, account_id, created_at, source_text, translated_text, context,
               app_name, bundle_id, source_kind, engine, target_language, is_favorite
        FROM queries
        WHERE account_id = ? \(whereFavorite) \(whereSearch)
        ORDER BY created_at DESC
        LIMIT ?;
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }

        try bind(accountID.uuidString, to: statement, index: 1)
        var nextIndex: Int32 = 2
        if !trimmedSearch.isEmpty {
            let pattern = "%\(trimmedSearch)%"
            for _ in 0..<4 {
                try bind(pattern, to: statement, index: nextIndex)
                nextIndex += 1
            }
        }
        sqlite3_bind_int(statement, nextIndex, Int32(max(0, limit)))

        var result: [QueryRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(readRecord(from: statement))
        }
        return result
    }

    func allRecords(accountID: UUID) throws -> [QueryRecord] {
        try records(accountID: accountID, limit: 100_000)
    }

    func updateTranslation(id: Int64, translatedText: String, engine: String) throws {
        let db = try requireDatabase()
        let statement = try prepare(
            "UPDATE queries SET translated_text = ?, engine = ? WHERE id = ?;",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        try bind(translatedText, to: statement, index: 1)
        try bind(engine, to: statement, index: 2)
        sqlite3_bind_int64(statement, 3, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError(db) }
    }

    func setFavorite(id: Int64, isFavorite: Bool) throws {
        let db = try requireDatabase()
        let statement = try prepare("UPDATE queries SET is_favorite = ? WHERE id = ?;", in: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError(db) }
    }

    func delete(id: Int64) throws {
        let db = try requireDatabase()
        let statement = try prepare("DELETE FROM queries WHERE id = ?;", in: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError(db) }
    }

    func stats(accountID: UUID) throws -> HistoryStats {
        let db = try requireDatabase()
        let sql = """
        SELECT COUNT(*), COALESCE(SUM(is_favorite), 0), COALESCE(SUM(LENGTH(source_text)), 0)
        FROM queries WHERE account_id = ?;
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }
        try bind(accountID.uuidString, to: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastError(db)
        }
        return HistoryStats(
            total: Int(sqlite3_column_int64(statement, 0)),
            favorites: Int(sqlite3_column_int64(statement, 1)),
            characters: Int(sqlite3_column_int64(statement, 2))
        )
    }

    func exportJSONL(accountID: UUID, to url: URL) throws {
        let records = try allRecords(accountID: accountID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var output = ""
        for record in records {
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else { continue }
            output += line + "\n"
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }


    func exportCSV(accountID: UUID, to url: URL) throws {
        let records = try allRecords(accountID: accountID)
        var lines = ["created_at,source,translation,context,app,engine,target_language,favorite"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            let fields = [
                formatter.string(from: record.createdAt),
                record.sourceText,
                record.translatedText,
                record.context,
                record.appName,
                record.engine,
                record.targetLanguage,
                record.isFavorite ? "1" : "0"
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\""
    }

    // MARK: - SQLite helpers

    private func createSchema(_ db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS queries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            source_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            context TEXT NOT NULL DEFAULT '',
            app_name TEXT NOT NULL DEFAULT '',
            bundle_id TEXT NOT NULL DEFAULT '',
            source_kind TEXT NOT NULL DEFAULT '',
            engine TEXT NOT NULL DEFAULT '',
            target_language TEXT NOT NULL DEFAULT '',
            is_favorite INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_queries_account_created
            ON queries(account_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_queries_account_favorite
            ON queries(account_id, is_favorite);
        """
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw HistoryStoreError.sqlite(message)
        }
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard let database else { throw HistoryStoreError.databaseUnavailable }
        if !didCreateSchema {
            try createSchema(database)
            didCreateSchema = true
        }
        return database
    }

    private func prepare(_ sql: String, in db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw lastError(db)
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw HistoryStoreError.sqlite("绑定文本失败")
        }
    }

    private func readRecord(from statement: OpaquePointer) -> QueryRecord {
        let id = sqlite3_column_int64(statement, 0)
        let accountID = UUID(uuidString: text(statement, 1)) ?? UUID()
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        return QueryRecord(
            id: id,
            accountID: accountID,
            createdAt: createdAt,
            sourceText: text(statement, 3),
            translatedText: text(statement, 4),
            context: text(statement, 5),
            appName: text(statement, 6),
            bundleID: text(statement, 7).isEmpty ? nil : text(statement, 7),
            sourceKind: text(statement, 8),
            engine: text(statement, 9),
            targetLanguage: text(statement, 10),
            isFavorite: sqlite3_column_int(statement, 11) != 0
        )
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func lastError(_ db: OpaquePointer) -> HistoryStoreError {
        HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}
