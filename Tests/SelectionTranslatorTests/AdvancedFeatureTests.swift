import XCTest
@testable import SelectionTranslator

final class AdvancedFeatureTests: XCTestCase {
    func testSettingsRoundTripKeepsNewReadingFields() throws {
        var settings = AppSettings()
        settings.translationStyle = .technical
        settings.autoTranslateOnSelection = true
        settings.excludedBundleIDs = ["com.apple.Terminal"]
        settings.glossary = [
            GlossaryEntry(term: "RAG", translation: "检索增强生成")
        ]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.translationStyle, .technical)
        XCTAssertTrue(decoded.autoTranslateOnSelection)
        XCTAssertEqual(decoded.excludedBundleIDs, ["com.apple.Terminal"])
        XCTAssertEqual(decoded.glossary.count, 1)
        XCTAssertTrue(decoded.glossary[0].isValid)
        XCTAssertTrue(decoded.isAppExcluded("com.apple.Terminal"))
        XCTAssertFalse(decoded.isAppExcluded(nil))
    }

    func testOldSettingsWithoutReadingFieldsUseDefaults() throws {
        var settings = AppSettings()
        settings.translationStyle = .natural
        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "translationStyle")
        object.removeValue(forKey: "glossary")
        object.removeValue(forKey: "autoTranslateOnSelection")
        object.removeValue(forKey: "excludedBundleIDs")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded.translationStyle, .natural)
        XCTAssertEqual(decoded.glossary, [])
        XCTAssertFalse(decoded.autoTranslateOnSelection)
        XCTAssertEqual(decoded.excludedBundleIDs, [])
    }

    func testPromptIncludesStyleAndOnlyValidGlossaryEntries() {
        let request = TranslationRequest(
            text: "RAG improves factual grounding.",
            context: "A paper abstract.",
            targetLanguage: "简体中文",
            model: "test",
            apiBaseURL: "https://example.com",
            apiKey: "",
            temperature: 0.2,
            maxOutputTokens: 256,
            style: .academic,
            glossary: [
                GlossaryEntry(term: "RAG", translation: "检索增强生成"),
                GlossaryEntry(term: "  ", translation: "空术语")
            ]
        )

        let messages = PromptBuilder.translationMessages(for: request)
        let system = messages.first { $0["role"] == "system" }?["content"] ?? ""
        let user = messages.first { $0["role"] == "user" }?["content"] ?? ""

        XCTAssertTrue(system.contains("academic register"))
        XCTAssertTrue(user.contains("RAG => 检索增强生成"))
        XCTAssertFalse(user.contains("空术语"))
    }

    func testTrimmerKeepsWindowAroundSelection() {
        let before = String(repeating: "old material line\n", count: 2_000)
        let selection = "TARGET SENTENCE"
        let after = String(repeating: "later material line\n", count: 2_000)
        let document = before + selection + "\n" + after

        let trimmed = DocumentContextTrimmer.trim(
            document,
            maxCharacters: 600,
            selection: selection
        )

        XCTAssertTrue(trimmed.contains(selection))
        XCTAssertLessThanOrEqual(trimmed.count, 600)
    }

    func testTrimmerFallsBackToHeadAndHandlesEmptyLimit() {
        let document = String(repeating: "first line\n", count: 1_000)
        let trimmed = DocumentContextTrimmer.trim(
            document,
            maxCharacters: 300,
            selection: "not in document"
        )
        XCTAssertTrue(trimmed.hasPrefix("first line"))
        XCTAssertLessThanOrEqual(trimmed.count, 300)
        XCTAssertEqual(DocumentContextTrimmer.trim(document, maxCharacters: 0, selection: "x"), "")
    }

    func testExternalURLCallerAllowlist() {
        XCTAssertTrue(ExternalURLCallerVerifier.isAllowed("com.apple.Safari"))
        XCTAssertTrue(ExternalURLCallerVerifier.isAllowed("com.google.Chrome"))
        XCTAssertTrue(ExternalURLCallerVerifier.isAllowed("com.apple.finder"))
        XCTAssertFalse(ExternalURLCallerVerifier.isAllowed("com.example.malware"))
        XCTAssertFalse(ExternalURLCallerVerifier.isAllowed(nil))
        XCTAssertFalse(ExternalURLCallerVerifier.isAllowed(""))
    }

    func testHistoryCipherRoundTripAndPrefix() throws {
        let cipher = HistoryCipher(keyOverride: Data(repeating: 0x33, count: 32))
        XCTAssertTrue(cipher.isAvailable)
        let encrypted = try cipher.encrypt("private reading")
        XCTAssertTrue(encrypted.hasPrefix(HistoryCipher.prefix))
        XCTAssertEqual(try cipher.decrypt(encrypted), "private reading")
        XCTAssertEqual(try cipher.decrypt("legacy plaintext"), "legacy plaintext")

        let wrong = HistoryCipher(keyOverride: Data(repeating: 0x44, count: 32))
        XCTAssertThrowsError(try wrong.decrypt(encrypted))
    }

    func testExternalURLGateEnforcesLengthAndRate() {
        var gate = ExternalURLGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(gate.accept(textLength: 0, now: start))
        XCTAssertFalse(gate.accept(textLength: ExternalURLGate.maxTextCharacters + 1, now: start))
        XCTAssertTrue(gate.accept(textLength: 10, now: start))

        for _ in 1..<ExternalURLGate.maxRequestsPerMinute {
            XCTAssertTrue(gate.accept(textLength: 10, now: start))
        }
        XCTAssertFalse(gate.accept(textLength: 10, now: start))
        XCTAssertTrue(gate.accept(textLength: 10, now: start.addingTimeInterval(61)))
    }

    func testDocumentContextRepositoryEncryptsAndMigratesLegacyPlaintext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentContextRepositoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            DocumentContextRepository.directoryOverride = nil
            DocumentContextRepository.keyOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        DocumentContextRepository.directoryOverride = directory
        DocumentContextRepository.keyOverride = Data(repeating: 0x42, count: 32)

        let accountID = UUID()
        let legacyURL = DocumentContextRepository.legacyFileURL(accountID: accountID)
        try "旧版明文上下文".write(to: legacyURL, atomically: true, encoding: .utf8)

        let migrated = DocumentContextRepository.read(accountID: accountID)
        XCTAssertEqual(migrated, "旧版明文上下文")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

        let encryptedURL = DocumentContextRepository.fileURL(accountID: accountID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))
        let raw = try Data(contentsOf: encryptedURL)
        XCTAssertFalse(String(data: raw, encoding: .utf8) == migrated)

        DocumentContextRepository.write("新的上下文", accountID: accountID)
        XCTAssertEqual(DocumentContextRepository.read(accountID: accountID), "新的上下文")

        let attributes = try FileManager.default.attributesOfItem(atPath: encryptedURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        DocumentContextRepository.clear(accountID: accountID)
        XCTAssertEqual(DocumentContextRepository.read(accountID: accountID), "")
    }
}
