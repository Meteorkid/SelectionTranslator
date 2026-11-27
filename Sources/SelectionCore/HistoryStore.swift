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
    private let encryptionKeyOverride: Data?
    private var cipher: HistoryCipher?

    init(databaseURL: URL? = nil, encryptionKey: Data? = nil) {
        let resolvedURL: URL
        if let databaseURL {
            resolvedURL = databaseURL
        } else {
            let directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SelectionTranslator", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            resolvedURL = directory.appendingPathComponent("history.sqlite3")
        }
        try? FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.databaseURL = resolvedURL
        self.encryptionKeyOverride = encryptionKey

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
        // Translation history is sensitive reading material. Field-level
        // encryption protects the content; 0600 restricts the database and
        // WAL/journal side files to the current user.
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
        let cipher = try requireCipher()
        let sql = """
        INSERT INTO queries
        (account_id, created_at, source_text, translated_text, context, app_name, bundle_id,
         source_kind, engine, target_language, is_favorite, char_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }

        try bind(record.accountID.uuidString, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, record.createdAt.timeIntervalSince1970)
        try bind(try cipher.encrypt(record.sourceText), to: statement, index: 3)
        try bind(try cipher.encrypt(record.translatedText), to: statement, index: 4)
        try bind(try cipher.encrypt(record.context), to: statement, index: 5)
        try bind(try cipher.encrypt(record.appName), to: statement, index: 6)
        try bind(try cipher.encrypt(record.bundleID ?? ""), to: statement, index: 7)
        try bind(record.sourceKind, to: statement, index: 8)
        try bind(record.engine, to: statement, index: 9)
        try bind(record.targetLanguage, to: statement, index: 10)
        sqlite3_bind_int(statement, 11, record.isFavorite ? 1 : 0)
        sqlite3_bind_int64(statement, 12, Int64(record.sourceText.count))

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
        guard limit > 0 else { return [] }
        let db = try requireDatabase()
        let cipher = currentCipher()
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLimit = Int32(max(0, limit))
        let whereFavorite = favoritesOnly ? "AND is_favorite = 1" : ""
        let scanLimit = trimmedSearch.isEmpty ? defaultLimit : 100_000
        let sql = """
        SELECT id, account_id, created_at, source_text, translated_text, context,
               app_name, bundle_id, source_kind, engine, target_language, is_favorite
        FROM queries
        WHERE account_id = ? \(whereFavorite)
        ORDER BY created_at DESC
        LIMIT ?;
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }

        try bind(accountID.uuidString, to: statement, index: 1)
        // Encrypted text cannot be searched with SQL LIKE: decrypt the
        // account's newest rows in memory and stop at the caller's limit.
        sqlite3_bind_int(statement, 2, Int32(scanLimit))

        var result: [QueryRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = readRecord(from: statement, cipher: cipher)
            if trimmedSearch.isEmpty
                || record.sourceText.localizedCaseInsensitiveContains(trimmedSearch)
                || record.translatedText.localizedCaseInsensitiveContains(trimmedSearch)
                || record.context.localizedCaseInsensitiveContains(trimmedSearch)
                || record.appName.localizedCaseInsensitiveContains(trimmedSearch) {
                result.append(record)
                if !trimmedSearch.isEmpty, result.count >= max(0, limit) { break }
            }
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
        let cipher = try requireCipher()
        try bind(try cipher.encrypt(translatedText), to: statement, index: 1)
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
        SELECT COUNT(*), COALESCE(SUM(is_favorite), 0),
               COALESCE(SUM(CASE WHEN char_count > 0 THEN char_count ELSE LENGTH(source_text) END), 0)
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
        // Spreadsheet apps evaluate formulas in CSV cells. A translation of a
        // page-controlled string such as "=HYPERLINK(...)" must remain text,
        // not execute when the user opens the export in Numbers/Excel.
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let formulaSafe: String
        if let first, "=+-@".contains(first) {
            formulaSafe = "'" + value
        } else {
            formulaSafe = value
        }
        let escaped = formulaSafe.replacingOccurrences(of: "\"", with: "\"\"")
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
            is_favorite INTEGER NOT NULL DEFAULT 0,
            char_count INTEGER NOT NULL DEFAULT 0
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
            try ensureColumns(database)
            try migrateLegacyRows(database)
            didCreateSchema = true
        }
        return database
    }

    private func ensureColumns(_ db: OpaquePointer) throws {
        try addColumnIfNeeded(
            "char_count",
            definition: "INTEGER NOT NULL DEFAULT 0",
            in: db
        )
    }

    private func addColumnIfNeeded(
        _ name: String,
        definition: String,
        in db: OpaquePointer
    ) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            db,
            "ALTER TABLE queries ADD COLUMN \(name) \(definition);",
            nil,
            nil,
            &errorPointer
        )
        if result == SQLITE_OK {
            sqlite3_free(errorPointer)
            return
        }
        let message = errorPointer.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(errorPointer)
        if message.contains("duplicate column name") {
            return
        }
        throw HistoryStoreError.sqlite(message)
    }

    /// Encrypt legacy plaintext rows in place once a key is available. If the
    /// Keychain is unavailable, keep the plaintext readable and retry on the
    /// next launch instead of losing the user's history.
    private func migrateLegacyRows(_ db: OpaquePointer) throws {
        // Select any row that still has a non-empty plaintext field, or an
        // encrypted row whose character count has not been backfilled. This
        // also repairs rows left half-migrated by an interrupted write.
        let selectSQL = """
        SELECT id, source_text, translated_text, context, app_name, bundle_id, char_count
        FROM queries
        WHERE (source_text <> '' AND source_text NOT LIKE 'enc:v1:%')
           OR (translated_text <> '' AND translated_text NOT LIKE 'enc:v1:%')
           OR (context <> '' AND context NOT LIKE 'enc:v1:%')
           OR (app_name <> '' AND app_name NOT LIKE 'enc:v1:%')
           OR (bundle_id <> '' AND bundle_id NOT LIKE 'enc:v1:%')
           OR (char_count = 0 AND source_text <> '');
        """
        let select = try prepare(selectSQL, in: db)
        defer { sqlite3_finalize(select) }

        let update = try prepare(
            "UPDATE queries SET source_text = ?, translated_text = ?, context = ?, app_name = ?, bundle_id = ?, char_count = ? WHERE id = ?;",
            in: db
        )
        defer { sqlite3_finalize(update) }

        var loadedCipher: HistoryCipher?
        while sqlite3_step(select) == SQLITE_ROW {
            // Loading the Keychain key is deferred until there is a row that
            // actually needs migration; a normal encrypted database can be
            // opened for stats without showing a Keychain prompt.
            let cipher = loadedCipher ?? currentCipher()
            loadedCipher = cipher

            let id = sqlite3_column_int64(select, 0)
            let source = text(select, 1)
            let translation = text(select, 2)
            let context = text(select, 3)
            let appName = text(select, 4)
            let bundleID = text(select, 5)
            let existingCount = sqlite3_column_int64(select, 6)

            let encryptedSource = try encryptedIfNeeded(source, cipher: cipher)
            let encryptedTranslation = try encryptedIfNeeded(translation, cipher: cipher)
            let encryptedContext = try encryptedIfNeeded(context, cipher: cipher)
            let encryptedAppName = try encryptedIfNeeded(appName, cipher: cipher)
            let encryptedBundleID = try encryptedIfNeeded(bundleID, cipher: cipher)

            let characterCount: Int64
            if HistoryCipher.isEncrypted(source) {
                characterCount = (try? cipher.decrypt(source)).map { Int64($0.count) } ?? existingCount
            } else {
                characterCount = Int64(source.count)
            }

            try bind(encryptedSource, to: update, index: 1)
            try bind(encryptedTranslation, to: update, index: 2)
            try bind(encryptedContext, to: update, index: 3)
            try bind(encryptedAppName, to: update, index: 4)
            try bind(encryptedBundleID, to: update, index: 5)
            sqlite3_bind_int64(update, 6, characterCount)
            sqlite3_bind_int64(update, 7, id)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw lastError(db)
            }
            sqlite3_reset(update)
            sqlite3_clear_bindings(update)
        }
    }

    private func encryptedIfNeeded(
        _ value: String,
        cipher: HistoryCipher
    ) throws -> String {
        guard cipher.isAvailable, !HistoryCipher.isEncrypted(value) else {
            return value
        }
        return try cipher.encrypt(value)
    }

    private func currentCipher() -> HistoryCipher {
        if let cipher { return cipher }
        let loaded = HistoryCipher(keyOverride: encryptionKeyOverride)
        cipher = loaded
        return loaded
    }

    private func requireCipher() throws -> HistoryCipher {
        let loaded = currentCipher()
        guard loaded.isAvailable else {
            throw HistoryCipherError.keyUnavailable
        }
        return loaded
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

    private func readRecord(
        from statement: OpaquePointer,
        cipher: HistoryCipher
    ) -> QueryRecord {
        let id = sqlite3_column_int64(statement, 0)
        let accountID = UUID(uuidString: text(statement, 1)) ?? UUID()
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let source = decrypted(text(statement, 3), cipher: cipher)
        let translation = decrypted(text(statement, 4), cipher: cipher)
        let context = decrypted(text(statement, 5), cipher: cipher)
        let appName = decrypted(text(statement, 6), cipher: cipher)
        let bundleID = decrypted(text(statement, 7), cipher: cipher)
        return QueryRecord(
            id: id,
            accountID: accountID,
            createdAt: createdAt,
            sourceText: source,
            translatedText: translation,
            context: context,
            appName: appName,
            bundleID: bundleID.isEmpty ? nil : bundleID,
            sourceKind: text(statement, 8),
            engine: text(statement, 9),
            targetLanguage: text(statement, 10),
            isFavorite: sqlite3_column_int(statement, 11) != 0
        )
    }

    private func decrypted(_ value: String, cipher: HistoryCipher) -> String {
        guard HistoryCipher.isEncrypted(value) else { return value }
        return (try? cipher.decrypt(value)) ?? "🔒 历史不可解密"
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func lastError(_ db: OpaquePointer) -> HistoryStoreError {
        HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}
