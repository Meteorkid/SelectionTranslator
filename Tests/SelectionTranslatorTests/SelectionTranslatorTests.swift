import XCTest
import SQLite3
@testable import SelectionTranslator

final class PromptBuilderTests: XCTestCase {
    func testDocumentBlockAndSelectionInstruction() {
        let request = TranslationRequest(
            text: "ubiquitous",
            context: "The smartphone has become ubiquitous.",
            targetLanguage: "简体中文",
            model: "qwen2.5:3b",
            apiBaseURL: "http://127.0.0.1:11434/v1",
            apiKey: "",
            temperature: 0.2,
            maxOutputTokens: 128,
            documentContext: "This is a long article about mobile computing."
        )

        let messages = PromptBuilder.translationMessages(for: request)
        XCTAssertEqual(messages.count, 2)
        let user = messages[1]["content"] ?? ""
        XCTAssertTrue(user.contains("<document>"))
        XCTAssertTrue(user.contains("This is a long article about mobile computing."))
        XCTAssertTrue(user.contains("<context>"))
        XCTAssertTrue(user.contains("The smartphone has become ubiquitous."))
        XCTAssertTrue(user.contains("<selection>"))
        XCTAssertTrue(user.contains("ubiquitous"))
        XCTAssertTrue(user.contains("Do not quote or translate the whole document; only translate <selection>."))
    }

    func testNoDocumentBlockWhenEmpty() {
        let request = TranslationRequest(
            text: "hello",
            context: "",
            targetLanguage: "English",
            model: "m",
            apiBaseURL: "http://127.0.0.1:11434/v1",
            apiKey: "",
            temperature: 0,
            maxOutputTokens: 32,
            documentContext: ""
        )
        let user = PromptBuilder.translationMessages(for: request)[1]["content"] ?? ""
        XCTAssertFalse(user.contains("<document>"))
        XCTAssertTrue(user.contains("<selection>"))
    }
}

final class SettingsMigrationTests: XCTestCase {
    func testLegacySettingsFillNewDefaults() throws {
        let json = """
        {"apiBaseURL":"http://127.0.0.1:11434/v1","model":"qwen2.5:3b","providerName":""}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.providerName, "Ollama")
        XCTAssertTrue(settings.enableMouseSelection)
        XCTAssertTrue(settings.useDocumentContext)
        XCTAssertEqual(settings.documentContextMaxChars, 6_000)
        XCTAssertEqual(settings.ankiURL, "http://127.0.0.1:8765")
        XCTAssertEqual(settings.appearance, .native)
    }

    func testAppearanceRoundTrip() throws {
        var settings = AppSettings()
        settings.appearance = .liquidGlass
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.appearance, .liquidGlass)
    }

    func testLanguageCatalogShape() {
        XCTAssertEqual(LanguageCatalog.targets.count, 52)
        XCTAssertEqual(LanguageCatalog.promptName(for: "简体中文"), "Simplified Chinese")
        XCTAssertEqual(LanguageCatalog.systemIdentifier(for: "日本語"), "ja")
        XCTAssertEqual(LanguageCatalog.option(named: "不存在").displayName, "简体中文")
    }
}

final class TranslationKeyTests: XCTestCase {
    func testCacheKeyIncludesAccountAndDocument() {
        let settings = AppSettings()
        let accountA = UUID()
        let accountB = UUID()

        let keyA = TranslationPipeline.cacheKey(
            text: "word",
            context: "ctx",
            documentContext: "doc-a",
            accountID: accountA,
            settings: settings
        )
        let keyB = TranslationPipeline.cacheKey(
            text: "word",
            context: "ctx",
            documentContext: "doc-b",
            accountID: accountA,
            settings: settings
        )
        let keyC = TranslationPipeline.cacheKey(
            text: "word",
            context: "ctx",
            documentContext: "doc-a",
            accountID: accountB,
            settings: settings
        )

        XCTAssertNotEqual(keyA, keyB)
        XCTAssertNotEqual(keyA, keyC)

        var styled = settings
        styled.translationStyle = .technical
        let styleKey = TranslationPipeline.cacheKey(
            text: "word",
            context: "ctx",
            documentContext: "doc-a",
            accountID: accountA,
            settings: styled
        )
        XCTAssertNotEqual(keyA, styleKey)

        styled.glossary = [GlossaryEntry(term: "word", translation: "词")]
        let glossaryKey = TranslationPipeline.cacheKey(
            text: "word",
            context: "ctx",
            documentContext: "doc-a",
            accountID: accountA,
            settings: styled
        )
        XCTAssertNotEqual(styleKey, glossaryKey)
    }
}

final class AppURLParserTests: XCTestCase {
    func testTranslateURLDecodesPlusAsSpaceButKeepsEncodedPlus() {
        let url = URL(string: "selectiontranslator://translate?text=hello+world&context=a%2Bb&document=page+body&app=Chrome&title=Example")!
        guard case .translate(let request) = AppURLParser.parse(url) else {
            return XCTFail("expected translate command")
        }
        XCTAssertEqual(request.text, "hello world")
        XCTAssertEqual(request.context, "a+b")
        XCTAssertEqual(request.documentContext, "page body")
        XCTAssertEqual(request.appName, "Chrome")
        XCTAssertEqual(request.title, "Example")
    }

    func testSimpleCommands() {
        XCTAssertEqual(AppURLParser.parse(URL(string: "selectiontranslator://clipboard")!), .clipboard)
        XCTAssertEqual(AppURLParser.parse(URL(string: "selectiontranslator://silent-ocr")!), .silentOCR)
        XCTAssertEqual(AppURLParser.parse(URL(string: "selectiontranslator://library")!), .library)
        XCTAssertEqual(AppURLParser.parse(URL(string: "selectiontranslator://settings")!), .settings)
    }

    func testUnknownAndWrongScheme() {
        XCTAssertEqual(AppURLParser.parse(URL(string: "selectiontranslator://nope")!), .unknown("nope"))
        XCTAssertNil(AppURLParser.parse(URL(string: "https://example.com")!))
    }
}

final class HistoryStoreTests: XCTestCase {
    func testInsertStatsAndCSVExport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectionTranslatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        let csvURL = directory.appendingPathComponent("history.csv")
        defer { try? FileManager.default.removeItem(at: directory) }

        let encryptionKey = Data(repeating: 0x5A, count: 32)
        let store = HistoryStore(databaseURL: databaseURL, encryptionKey: encryptionKey)
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let accountID = UUID()
        let record = QueryRecord(
            accountID: accountID,
            sourceText: "a,\"b\"\nline",
            translatedText: "译文",
            context: "ctx",
            appName: "UnitTest",
            sourceKind: "accessibility",
            engine: "model",
            targetLanguage: "简体中文",
            isFavorite: true
        )
        _ = try await store.insert(record)

        let stats = try await store.stats(accountID: accountID)
        XCTAssertEqual(stats.total, 1)
        XCTAssertEqual(stats.favorites, 1)
        XCTAssertEqual(stats.characters, 10)

        let records = try await store.records(accountID: accountID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceText, record.sourceText)
        XCTAssertEqual(records.first?.translatedText, "译文")

        let storedSource = try rawColumn("source_text", at: databaseURL)
        XCTAssertTrue(storedSource.hasPrefix(HistoryCipher.prefix))
        XCTAssertFalse(storedSource.contains("a,\"b\""))

        let searched = try await store.records(accountID: accountID, search: "译文")
        XCTAssertEqual(searched.count, 1)
        let noMatch = try await store.records(accountID: accountID, search: "missing")
        XCTAssertTrue(noMatch.isEmpty)

        try await store.exportCSV(accountID: accountID, to: csvURL)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("created_at,source,translation"))
        XCTAssertTrue(csv.contains("\"译文\""))
        XCTAssertTrue(csv.contains("\"\"b\"\"") || csv.contains("\"a,\"\"b\"\"\nline\""))
        XCTAssertTrue(csv.contains("\"1\""))
    }

    func testLegacyPlaintextRowsAreMigrated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        let accountID = UUID()

        let oldSchema = """
        CREATE TABLE queries (
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
        INSERT INTO queries
        (account_id, created_at, source_text, translated_text, context, app_name, bundle_id,
         source_kind, engine, target_language, is_favorite)
        VALUES ('\(accountID.uuidString)', 1000, 'legacy secret', '旧译文', '旧上下文',
                'Notes', 'com.apple.Notes', 'accessibility', 'model', '简体中文', 0);
        """
        try execute(oldSchema, at: databaseURL)

        let store = HistoryStore(
            databaseURL: databaseURL,
            encryptionKey: Data(repeating: 0x6B, count: 32)
        )
        let records = try await store.records(accountID: accountID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceText, "legacy secret")
        XCTAssertEqual(records.first?.translatedText, "旧译文")

        let storedSource = try rawColumn("source_text", at: databaseURL)
        XCTAssertTrue(storedSource.hasPrefix(HistoryCipher.prefix))
        XCTAssertFalse(storedSource.contains("legacy secret"))
    }

    func testHalfMigratedRowIsRepairedAndCountBackfilled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryPartialMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite3")
        let accountID = UUID()
        let key = Data(repeating: 0x7C, count: 32)
        let cipher = HistoryCipher(keyOverride: key)
        let encryptedSource = try cipher.encrypt("partial source")

        let schema = """
        CREATE TABLE queries (
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
        INSERT INTO queries
        (account_id, created_at, source_text, translated_text, context, app_name, bundle_id, char_count)
        VALUES ('\(accountID.uuidString)', 1001, '\(encryptedSource)', 'plain translation',
                '', '', '', 0);
        """
        try execute(schema, at: databaseURL)

        let store = HistoryStore(databaseURL: databaseURL, encryptionKey: key)
        let records = try await store.records(accountID: accountID)
        XCTAssertEqual(records.first?.sourceText, "partial source")
        XCTAssertEqual(records.first?.translatedText, "plain translation")

        let storedTranslation = try rawColumn("translated_text", at: databaseURL)
        XCTAssertTrue(storedTranslation.hasPrefix(HistoryCipher.prefix))
        let stats = try await store.stats(accountID: accountID)
        XCTAssertEqual(stats.characters, "partial source".count)
    }

    private func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw HistoryStoreError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw HistoryStoreError.sqlite(message)
        }
    }

    private func rawColumn(_ column: String, at url: URL) throws -> String {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw HistoryStoreError.databaseUnavailable
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT \(column) FROM queries ORDER BY id DESC LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return ""
        }
        return String(cString: text)
    }
}
