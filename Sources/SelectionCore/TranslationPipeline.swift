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
        apiKey: String,
        accountID: UUID? = nil
    ) -> TranslationRoute {
        let text = capture.selectedText
        let cacheKey = cacheKey(
            text: text,
            context: capture.context,
            documentContext: capture.documentContext,
            accountID: accountID,
            settings: settings
        )

        if settings.useAppleDictionary,
           OfflineDictionary.isLookupCandidate(text),
           let definition = AppleDictionaryService.lookup(text) {
            return .offlineDictionary(definition, engine: "系统词典")
        }

        if OfflineDictionary.isLookupCandidate(text),
           let definition = OfflineDictionary.shared.lookup(text) {
            return .offlineDictionary(definition, engine: "离线词库")
        }

        if let cached = TranslationCache.shared.value(for: cacheKey), !cached.isEmpty {
            return .cache(cached)
        }

        if !apiKey.isEmpty || settings.isUsableWithoutKey {
            return .model(
                TranslationRequest(
                    text: text,
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
            )
        }

        if #available(macOS 15.0, *) {
            return .system
        }

        return .unavailable(
            "这台 Mac 上没有可用的翻译引擎。可以安装 Ollama、填 API Key，或升级到 macOS 15 使用系统翻译。"
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
                .map { "\($0.term)=\($0.translation)" }
                .joined(separator: "\u{1F}"),
            settings.model,
            settings.apiBaseURL,
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
