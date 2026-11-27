import XCTest
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

        let store = HistoryStore(databaseURL: databaseURL)
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

        try await store.exportCSV(accountID: accountID, to: csvURL)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("created_at,source,translation"))
        XCTAssertTrue(csv.contains("\"译文\""))
        XCTAssertTrue(csv.contains("\"\"b\"\"") || csv.contains("\"a,\"\"b\"\"\nline\""))
        XCTAssertTrue(csv.contains("\"1\""))
    }
}
