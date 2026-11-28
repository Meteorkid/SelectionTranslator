import Foundation

final class TranslationCache: @unchecked Sendable {
    static let shared = TranslationCache()

    private let cache = NSCache<NSString, NSString>()

    private init() {
        cache.countLimit = 300
    }

    func value(for key: String) -> String? {
        cache.object(forKey: key as NSString) as String?
    }

    func store(_ translation: String, for key: String) {
        guard !translation.isEmpty else { return }
        cache.setObject(translation as NSString, forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

enum TranslationRoute: Sendable {
    case offlineDictionary(String, engine: String)
    case cache(String)
    case model(TranslationRequest)
    /// The model path is viable only after resolving the API key. Keeping this
    /// as a separate route lets dictionary/cache results avoid touching the
    /// Keychain at all.
    case needsAPIKey
    case system
    case unavailable(String)
}

enum TranslationPipeline {
    static func canUseModel(settings: AppSettings, apiKey: String) -> Bool {
        !apiKey.isEmpty || settings.isUsableWithoutKey
    }

    static func route(
        capture: CaptureResult,
        settings: AppSettings,
        accountID: UUID? = nil
    ) async -> TranslationRoute {
        let text = capture.selectedText
        let cacheKey = cacheKey(
            text: text,
            context: capture.context,
            documentContext: capture.documentContext,
            accountID: accountID,
            settings: settings
        )

        // Dictionary Services and the bundled TSV are synchronous. Run them
        // off the main actor so a cold dictionary lookup cannot hitch the
        // panel animation or the first keystroke in the input window.
        if OfflineDictionary.isLookupCandidate(text) {
            let dictionaryRoute: TranslationRoute? = await Task.detached(
                priority: .userInitiated
            ) { () -> TranslationRoute? in
                if settings.useAppleDictionary,
                   let definition = AppleDictionaryService.lookup(text) {
                    return TranslationRoute.offlineDictionary(
                        definition,
                        engine: "系统词典"
                    )
                }
                if let definition = OfflineDictionary.shared.lookup(text) {
                    return TranslationRoute.offlineDictionary(
                        definition,
                        engine: "离线词库"
                    )
                }
                return nil
            }.value
            if let dictionaryRoute { return dictionaryRoute }
        }

        if let cached = TranslationCache.shared.value(for: cacheKey), !cached.isEmpty {
            return .cache(cached)
        }

        if settings.isUsableWithoutKey {
            return .model(request(capture: capture, settings: settings, apiKey: ""))
        }

        return .needsAPIKey
    }

    static func request(
        capture: CaptureResult,
        settings: AppSettings,
        apiKey: String
    ) -> TranslationRequest {
        TranslationRequest(
            text: capture.selectedText,
            context: capture.context,
            targetLanguage: settings.targetLanguage,
            model: settings.model,
            apiBaseURL: settings.apiBaseURL,
            apiKey: apiKey,
            temperature: settings.temperature,
            maxOutputTokens: settings.maxOutputTokens,
            documentContext: capture.documentContext,
            style: settings.translationStyle,
            glossary: settings.glossary
        )
    }

    static func cacheKey(
        text: String,
        context: String,
        documentContext: String = "",
        accountID: UUID? = nil,
        settings: AppSettings
    ) -> String {
        [
            accountID?.uuidString ?? "",
            settings.targetLanguage,
            settings.translationStyle.rawValue,
            settings.glossary
                .filter(\.isValid)
                .prefix(64)
                .map { "\($0.term.prefix(200))=\($0.translation.prefix(400))" }
                .joined(separator: "\u{1F}"),
            settings.model,
            settings.apiBaseURL,
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), settings.temperature),
            String(settings.maxOutputTokens),
            text,
            context,
            documentContext
        ].joined(separator: "\u{1F}")
    }

    static func storeInCache(
        translation: String,
        capture: CaptureResult,
        settings: AppSettings,
        accountID: UUID? = nil
    ) {
        guard !translation.isEmpty else { return }
        TranslationCache.shared.store(
            translation,
            for: cacheKey(
                text: capture.selectedText,
                context: capture.context,
                documentContext: capture.documentContext,
                accountID: accountID,
                settings: settings
            )
        )
    }
}
