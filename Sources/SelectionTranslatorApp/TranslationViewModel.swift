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
    private var capture: CaptureResult?
    private var settings: AppSettings?
    private var apiKey = ""
    private var accountID: UUID?
    private var didPersist = false

    func start(capture: CaptureResult, settings: AppSettings, apiKey: String, accountID: UUID) {
        task?.cancel()
        task = nil
        explainTask?.cancel()
        explainTask = nil

        self.capture = capture
        self.settings = settings
        self.apiKey = apiKey
        self.accountID = accountID
        didPersist = false
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
        isStreaming = false

        let route = TranslationPipeline.route(
            capture: capture,
            settings: settings,
            apiKey: apiKey,
            accountID: accountID
        )
        execute(route)
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
            persistIfNeeded()

        case .model(let request):
            startModel(request: request)

        case .system:
            engineLabel = "系统翻译"
            isStreaming = true
            needsSystemTranslation = true

        case .unavailable(let message):
            engineLabel = "无可用引擎"
            errorMessage = message
            isStreaming = false
        }
    }

    private func startModel(request: TranslationRequest) {
        engineLabel = settings?.isLocalProvider == true ? "本地模型" : "在线模型"
        isStreaming = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = OpenAICompatibleProvider().stream(request)
                for try await delta in stream {
                    try Task.checkCancellation()
                    self.translation += delta
                }
                self.isStreaming = false
                self.cacheAndPersist()
            } catch is CancellationError {
                self.isStreaming = false
            } catch {
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
        errorMessage = nil
        isStreaming = true
        needsSystemTranslation = true
    }

    func applySystemTranslation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            applySystemTranslationError("系统翻译没有返回内容。")
            return
        }
        translation = trimmed
        errorMessage = nil
        isStreaming = false
        needsSystemTranslation = false
        cacheAndPersist()
    }

    func applySystemTranslationError(_ message: String) {
        errorMessage = message
        isStreaming = false
        needsSystemTranslation = false
    }

    func toggleFavorite() {
        guard let recordID else { return }
        let newValue = !isFavorite
        Task { [weak self] in
            do {
                try await HistoryStore.shared.setFavorite(id: recordID, isFavorite: newValue)
                await MainActor.run {
                    self?.isFavorite = newValue
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
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

        let request = TranslationRequest(
            text: capture.selectedText,
            context: capture.context,
            targetLanguage: settings.targetLanguage,
            model: settings.model,
            apiBaseURL: settings.apiBaseURL,
            apiKey: apiKey,
            temperature: settings.temperature,
            maxOutputTokens: settings.maxOutputTokens,
            documentContext: capture.documentContext
        )

        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = OpenAICompatibleProvider().stream(request)
                for try await delta in stream {
                    try Task.checkCancellation()
                    self.contextExplanation += delta
                }
                self.isExplaining = false
                let explanation = self.contextExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !explanation.isEmpty else {
                    self.explanationError = "模型没有返回语境解释。"
                    self.engineLabel = "离线词库"
                    return
                }
                if let recordID = self.recordID {
                    let combined = self.translation + "\n\n语境解释：\n" + explanation
                    try? await HistoryStore.shared.updateTranslation(
                        id: recordID,
                        translatedText: combined,
                        engine: "离线词库 + 语境"
                    )
                }
            } catch is CancellationError {
                self.isExplaining = false
                self.engineLabel = "离线词库"
            } catch {
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
        task?.cancel()
        task = nil
        explainTask?.cancel()
        explainTask = nil
        needsSystemTranslation = false
        isStreaming = false
        isExplaining = false
    }

    private func cacheAndPersist() {
        if let capture, let settings {
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
                    self?.recordID = insertedID
                    self?.canFavorite = true
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "保存历史失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
