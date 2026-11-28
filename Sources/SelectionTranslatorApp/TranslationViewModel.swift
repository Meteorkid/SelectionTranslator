import Foundation
import Combine

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var contextText = ""
    @Published var documentContextText = ""
    @Published var translation = ""
    @Published var errorMessage: String?
    @Published var isStreaming = false
    @Published var appName = ""
    @Published var sourceKind = ""
    @Published var sourceLabel = ""
    @Published var engineLabel = ""
    @Published var needsSystemTranslation = false
    @Published var systemTargetLanguage = "简体中文"
    @Published var recordID: Int64?
    @Published var isFavorite = false
    @Published var canFavorite = false
    @Published var enableTTS = true
    @Published var canExplainInContext = false
    @Published var contextExplanation = ""
    @Published var isExplaining = false
    @Published var explanationError: String?

    private var task: Task<Void, Never>?
    private var explainTask: Task<Void, Never>?
    /// Invalidates callbacks from a previous translation after retry/cancel.
    private var runGeneration = 0
    /// Identifies the current system-translation request so a late response
    /// from an earlier request cannot overwrite a newer one.
    @Published private(set) var systemToken = UUID()
    private var capture: CaptureResult?
    private var settings: AppSettings?
    private var apiKey = ""
    private var accountID: UUID?
    private var didPersist = false
    private var modelFallbackError: String?

    func start(capture: CaptureResult, settings: AppSettings, apiKey: String, accountID: UUID) {
        task?.cancel()
        task = nil
        explainTask?.cancel()
        explainTask = nil
        runGeneration += 1
        systemToken = UUID()

        self.capture = capture
        self.settings = settings
        self.apiKey = apiKey
        self.accountID = accountID
        didPersist = false
        modelFallbackError = nil
        recordID = nil
        isFavorite = false
        canFavorite = false
        enableTTS = settings.enableTTS
        canExplainInContext = false
        contextExplanation = ""
        isExplaining = false
        explanationError = nil

        sourceText = capture.selectedText
        contextText = capture.context
        documentContextText = capture.documentContext
        appName = capture.appName
        sourceKind = capture.source.rawValue
        sourceLabel = capture.source.displayName
        translation = ""
        errorMessage = nil
        engineLabel = ""
        needsSystemTranslation = false
        systemTargetLanguage = settings.targetLanguage
        // A dictionary lookup or cache hit resolves quickly, but showing the
        // progress row avoids a blank panel while the async route is chosen.
        isStreaming = true

        let generation = runGeneration
        Task { [weak self] in
            let route = await TranslationPipeline.route(
                capture: capture,
                settings: settings,
                apiKey: apiKey,
                accountID: accountID
            )
            await MainActor.run {
                guard let self, self.runGeneration == generation else { return }
                self.execute(route)
            }
        }
    }

    func start(
        text: String,
        context: String = "",
        appName: String = "输入翻译",
        source: CaptureSource = .input,
        settings: AppSettings,
        apiKey: String,
        accountID: UUID,
        documentContext: String = ""
    ) {
        let capture = CaptureResult(
            selectedText: text,
            context: context,
            appName: appName,
            bundleID: nil,
            windowTitle: nil,
            source: source,
            documentContext: documentContext
        )
        start(capture: capture, settings: settings, apiKey: apiKey, accountID: accountID)
    }

    func retry() {
        guard let capture, let settings, let accountID else { return }
        start(capture: capture, settings: settings, apiKey: apiKey, accountID: accountID)
    }

    private func execute(_ route: TranslationRoute) {
        switch route {
        case .offlineDictionary(let definition, let engine):
            engineLabel = engine
            translation = definition
            isStreaming = false
            canExplainInContext = !captureContextEmpty
                && TranslationPipeline.canUseModel(settings: settings ?? AppSettings(), apiKey: apiKey)
            persistIfNeeded()

        case .cache(let cached):
            engineLabel = "缓存"
            translation = cached
            isStreaming = false
            canExplainInContext = !captureContextEmpty
                && TranslationPipeline.canUseModel(settings: settings ?? AppSettings(), apiKey: apiKey)
            persistIfNeeded()

        case .model(let request):
            startModel(request: request)

        case .system:
            engineLabel = "系统翻译"
            isStreaming = true
            requestSystemTranslation()

        case .unavailable(let message):
            engineLabel = "无可用引擎"
            errorMessage = message
            isStreaming = false
        }
    }

    private func startModel(request: TranslationRequest) {
        engineLabel = settings?.isLocalProvider == true ? "本地模型" : "在线模型"
        isStreaming = true
        let generation = runGeneration

        task = Task { [weak self] in
            guard let self, self.runGeneration == generation else { return }
            do {
                let stream = OpenAICompatibleProvider().stream(request)
                for try await delta in stream {
                    try Task.checkCancellation()
                    guard self.runGeneration == generation else { return }
                    self.translation += delta
                }
                guard self.runGeneration == generation else { return }
                self.isStreaming = false
                self.cacheAndPersist()
            } catch is CancellationError {
                guard self.runGeneration == generation else { return }
                self.isStreaming = false
            } catch {
                guard self.runGeneration == generation else { return }
                self.isStreaming = false
                self.startSystemFallback(error: error)
            }
        }
    }

    /// 本地/在线模型请求失败时，不让面板停在错误上；有系统翻译就继续降级。
    private func startSystemFallback(error: Error? = nil) {
        guard #available(macOS 15.0, *) else {
            errorMessage = error?.localizedDescription ?? "模型请求失败。"
            return
        }
        engineLabel = "系统翻译"
        modelFallbackError = error?.localizedDescription
        errorMessage = nil
        requestSystemTranslation()
    }

    private func requestSystemTranslation() {
        systemToken = UUID()
        needsSystemTranslation = true
        isStreaming = true
    }

    func applySystemTranslation(_ text: String, token: UUID) {
        guard token == systemToken, needsSystemTranslation else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            applySystemTranslationError("系统翻译没有返回内容。", token: token)
            return
        }
        translation = trimmed
        errorMessage = nil
        modelFallbackError = nil
        isStreaming = false
        needsSystemTranslation = false
        // A system-fallback result is not a model result. Caching it under
        // the model request key would silently serve it on the next lookup
        // even if the configured API starts working again.
        cacheAndPersist(cache: false)
    }

    func applySystemTranslationError(_ message: String, token: UUID) {
        guard token == systemToken, needsSystemTranslation else { return }
        if let modelFallbackError {
            errorMessage = "模型请求失败：\(modelFallbackError)\n系统翻译也未完成：\(message)"
        } else {
            errorMessage = message
        }
        isStreaming = false
        needsSystemTranslation = false
    }

    func toggleFavorite() {
        guard let recordID else { return }
        let newValue = !isFavorite
        let generation = runGeneration
        Task { [weak self] in
            do {
                try await HistoryStore.shared.setFavorite(id: recordID, isFavorite: newValue)
                await MainActor.run {
                    guard let self, self.runGeneration == generation else { return }
                    self.isFavorite = newValue
                }
            } catch {
                await MainActor.run {
                    guard let self, self.runGeneration == generation else { return }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// For a single word, the offline dictionary is instant but generic.
    /// Let the user ask the model for a second pass grounded in the saved context.
    func explainInContext() {
        guard canExplainInContext,
              !isExplaining,
              let capture,
              let settings else { return }

        explanationError = nil
        contextExplanation = ""
        isExplaining = true
        engineLabel = "离线词库 + 语境"
        let generation = runGeneration

        let request = TranslationRequest(
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

        explainTask = Task { [weak self] in
            guard let self, self.runGeneration == generation else { return }
            do {
                let stream = OpenAICompatibleProvider().stream(request)
                for try await delta in stream {
                    try Task.checkCancellation()
                    guard self.runGeneration == generation else { return }
                    self.contextExplanation += delta
                }
                guard self.runGeneration == generation else { return }
                self.isExplaining = false
                let explanation = self.contextExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !explanation.isEmpty else {
                    self.explanationError = "模型没有返回语境解释。"
                    self.engineLabel = "离线词库"
                    return
                }
                if let recordID = self.recordID {
                    let combined = self.translation + "\n\n语境解释：\n" + explanation
                    do {
                        try await HistoryStore.shared.updateTranslation(
                            id: recordID,
                            translatedText: combined,
                            engine: "离线词库 + 语境"
                        )
                    } catch {
                        guard self.runGeneration == generation else { return }
                        self.explanationError = "语境解释已生成，但保存到历史失败：\(error.localizedDescription)"
                    }
                }
            } catch is CancellationError {
                guard self.runGeneration == generation else { return }
                self.isExplaining = false
                self.engineLabel = "离线词库"
            } catch {
                guard self.runGeneration == generation else { return }
                self.isExplaining = false
                self.engineLabel = "离线词库"
                self.explanationError = "语境解释失败：\(error.localizedDescription)"
            }
        }
    }

    private var captureContextEmpty: Bool {
        capture?.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    func speakSource() {
        SpeechService.shared.speak(sourceText)
    }

    func speakTranslation() {
        SpeechService.shared.speak(translation)
    }

    func cancel() {
        runGeneration += 1
        systemToken = UUID()
        task?.cancel()
        task = nil
        explainTask?.cancel()
        explainTask = nil
        needsSystemTranslation = false
        isStreaming = false
        isExplaining = false
    }

    /// Clears the current result when the active local account changes. The
    /// old record belongs to the old account and must not be favorited from a
    /// window that now displays a different account.
    func reset() {
        cancel()
        capture = nil
        settings = nil
        apiKey = ""
        accountID = nil
        didPersist = false
        modelFallbackError = nil
        sourceText = ""
        contextText = ""
        documentContextText = ""
        appName = ""
        sourceKind = ""
        sourceLabel = ""
        translation = ""
        errorMessage = nil
        engineLabel = ""
        recordID = nil
        isFavorite = false
        canFavorite = false
        canExplainInContext = false
        contextExplanation = ""
        isExplaining = false
        explanationError = nil
    }

    private func cacheAndPersist(cache: Bool = true) {
        if cache, let capture, let settings {
            TranslationPipeline.storeInCache(
                translation: translation,
                capture: capture,
                settings: settings,
                accountID: accountID
            )
        }
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard !didPersist,
              let capture,
              let accountID,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        didPersist = true

        let generation = runGeneration
        let record = QueryRecord(
            accountID: accountID,
            sourceText: capture.selectedText,
            translatedText: translation,
            context: capture.context,
            appName: capture.appName,
            bundleID: capture.bundleID,
            sourceKind: capture.source.rawValue,
            engine: engineLabel,
            targetLanguage: settings?.targetLanguage ?? systemTargetLanguage
        )

        Task { [weak self] in
            do {
                let insertedID = try await HistoryStore.shared.insert(record)
                await MainActor.run {
                    guard let self, self.runGeneration == generation else { return }
                    self.recordID = insertedID
                    self.canFavorite = true
                }
            } catch {
                await MainActor.run {
                    guard let self, self.runGeneration == generation else { return }
                    self.errorMessage = "保存历史失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
