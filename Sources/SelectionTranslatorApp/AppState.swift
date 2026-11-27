import Foundation
import AppKit
import Combine
import os.log

@MainActor
final class AppState: ObservableObject {
    @MainActor static private(set) var shared: AppState?
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "app")
    let settingsStore = SettingsStore()
    let accountStore = LocalAccountStore()

    private let panelController = TranslationPanelController()
    private let settingsWindowController = SettingsWindowController()
    private let inputWindowController = InputTranslationWindowController()
    private let libraryWindowController = LibraryWindowController()
    private let hotKeyManager = HotKeyManager()
    private let mouseSelectionMonitor = MouseSelectionMonitor()
    private let selectionIconController = SelectionIconController()
    private let onboardingController = OnboardingWindowController()

    private var captureTask: Task<Void, Never>?
    private var hasStartedUpdater = false
    private var settingsSink: AnyCancellable?
    private var activationObserver: NSObjectProtocol?
    private var hasShownPermissionHelp = false
    private var externalURLGate = ExternalURLGate()

    init() {
        AppState.shared = self
        panelController.appearanceProvider = { [weak self] in
            self?.settingsStore.settings.appearance ?? .native
        }
        hotKeyManager.actionHandler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .selection:
                self.translateSelection()
            case .clipboard:
                self.translateClipboard()
            case .input:
                self.openInput()
            case .ocr:
                self.translateOCR()
            case .silentOCR:
                self.copyOCRText()
            case .library:
                self.openLibrary()
            case .settings:
                self.openSettings()
            }
        }
        hotKeyManager.register(settingsStore.settings.hotkeys)

        mouseSelectionMonitor.onSelection = { [weak self] capture, point in
            guard let self else { return }
            guard !self.settingsStore.settings.isAppExcluded(capture.bundleID) else {
                self.selectionIconController.hide()
                return
            }

            if self.settingsStore.settings.autoTranslateOnSelection {
                self.translate(capture)
                return
            }

            self.selectionIconController.show(
                capture: capture,
                near: point,
                hoverToTranslate: self.settingsStore.settings.mouseHoverTranslate,
                onActivate: { [weak self] captured in
                    self?.translate(captured)
                }
            )
        }
        applyMouseSelectionSettings(settingsStore.settings)

        settingsSink = settingsStore.$settings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                self.hotKeyManager.register(settings.hotkeys)
                self.applyMouseSelectionSettings(settings)
            }

        // A user may grant Accessibility in System Settings while the app is
        // running. Re-apply the monitor when the app becomes active so mouse
        // selection starts without requiring a relaunch or a settings toggle.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applyMouseSelectionSettings(self.settingsStore.settings)
            }
        }
    }

    private func applyMouseSelectionSettings(_ settings: AppSettings) {
        mouseSelectionMonitor.maxContextLength = settings.contextLength
        if settings.enableMouseSelection {
            mouseSelectionMonitor.start()
        } else {
            mouseSelectionMonitor.stop()
            selectionIconController.hide()
        }
    }

    // MARK: - Selection mode (needs Accessibility)

    func translateSelection() {
        log.info("translateSelection triggered")

        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            log.info("accessibility not granted; showing help panel")
            showPermissionHelpOnce()
            return
        }

        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            guard let capture = await SelectionCaptureService.capture(
                maxContextLength: self.settingsStore.settings.contextLength,
                useClipboardFallback: self.settingsStore.settings.useClipboardFallback
            ) else {
                self.panelController.showError(
                    "没有取到选中文字。请在 Safari、Preview、Word、VS Code 等应用里选中一段英文，再按 \(self.settingsStore.settings.hotkeys.selection.display)。"
                )
                return
            }
            self.translate(capture)
        }
    }

    private func showPermissionHelpOnce() {
        if hasShownPermissionHelp {
            NSSound.beep()
            return
        }
        hasShownPermissionHelp = true

        panelController.showPermissionHelp(
            onOpenSettings: {
                Permissions.openAccessibilitySettings()
            },
            onUseClipboard: { [weak self] in
                self?.translateClipboard()
            },
            onClose: { [weak self] in
                self?.panelController.hide()
            }
        )
    }

    // MARK: - Clipboard mode (no Accessibility needed)

    func translateClipboard() {
        log.info("translateClipboard triggered")
        captureTask?.cancel()

        let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if raw.isEmpty {
            let pastedImage = NSPasteboard.general
                .readObjects(forClasses: [NSImage.self], options: nil)?
                .first as? NSImage
            if let pastedImage {
                guard settingsStore.settings.enableOCR else {
                    panelController.showError("截图 OCR 已在设置里关闭，剪贴板图片不会发送到识别引擎。")
                    return
                }
                captureTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let text = try await OCRService.recognize(image: pastedImage)
                        self.translate(
                            CaptureResult(
                                selectedText: String(text.prefix(8_000)),
                                context: "",
                                appName: "剪贴板图片",
                                bundleID: nil,
                                windowTitle: nil,
                                source: .ocr
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        self.panelController.showError("剪贴板图片识别失败：\(error.localizedDescription)")
                    }
                }
                return
            }
            panelController.showError("剪贴板里没有文字或图片。先复制一段文字，或复制一张截图，再按 \(settingsStore.settings.hotkeys.clipboard.display)。")
            return
        }

        let text = String(raw.prefix(8_000))
        let capture = CaptureResult(
            selectedText: text,
            context: "",
            appName: "剪贴板",
            bundleID: nil,
            windowTitle: nil,
            source: .clipboard
        )
        translate(capture)
    }

    // MARK: - OCR

    func translateOCR() {
        guard settingsStore.settings.enableOCR else {
            panelController.showError("截图 OCR 已在设置里关闭。")
            return
        }

        guard ensureScreenCapturePermission() else { return }
        log.info("OCR capture start")
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await OCRService.captureInteractiveText()
                guard !text.isEmpty else {
                    self.panelController.showError("没有识别到文字。")
                    return
                }
                self.translate(
                    CaptureResult(
                        selectedText: String(text.prefix(8_000)),
                        context: "",
                        appName: "截图 OCR",
                        bundleID: nil,
                        windowTitle: nil,
                        source: .ocr
                    )
                )
            } catch OCRServiceError.cancelled, is CancellationError {
                return
            } catch {
                self.panelController.showError("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    /// Easydict-style silent OCR: recognize the selected region and copy text only.
    func copyOCRText() {
        guard settingsStore.settings.enableOCR else {
            panelController.showError("截图 OCR 已在设置里关闭。")
            return
        }

        guard ensureScreenCapturePermission() else { return }
        log.info("silent OCR capture start")
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await OCRService.captureInteractiveText()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.panelController.showError("没有识别到文字。")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trimmed, forType: .string)
                self.log.info("silent OCR copied \(trimmed.count, privacy: .public) chars")
                NSSound(named: "Glass")?.play()
            } catch OCRServiceError.cancelled, is CancellationError {
                return
            } catch {
                self.panelController.showError("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Updates

    /// Sparkle owns the update UI, feed parsing, signature verification and
    /// installation. We only start it after launch/onboarding and forward the
    /// menu's "check now" action.
    func startUpdater() {
        guard !hasStartedUpdater else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil,
              environment["ST_DISABLE_UPDATER"] != "1" else {
            log.info("skipping Sparkle updater in test host")
            return
        }
        hasStartedUpdater = true
        _ = SparkleUpdater.shared
    }

    func checkForUpdates() {
        startUpdater()
        SparkleUpdater.shared.checkForUpdates()
    }

    // MARK: - Onboarding

    @discardableResult
    func presentOnboardingIfNeeded(force: Bool = false) -> Bool {
        let forcedForQA = ProcessInfo.processInfo.environment["ST_FORCE_ONBOARDING"] == "1"
        guard force || forcedForQA || OnboardingState.shouldShow() else { return false }

        onboardingController.show(
            appearance: settingsStore.settings.appearance,
            onOpenPrivacy: {
                SupportLinks.openPrivacy()
            },
            onComplete: { [weak self] in
                guard let self else { return }
                OnboardingState.markCompleted()
                self.applyMouseSelectionSettings(self.settingsStore.settings)
                self.startUpdater()
            }
        )
        return true
    }

    // MARK: - Input / library

    func openInput() {
        inputWindowController.show(
            store: settingsStore,
            accountStore: accountStore,
            onOpenLibrary: { [weak self] in
                self?.openLibrary()
            }
        )
    }

    func openLibrary() {
        libraryWindowController.show(accountStore: accountStore, settingsStore: settingsStore)
    }

    func openSettings() {
        settingsWindowController.show(
            store: settingsStore,
            accountStore: accountStore,
            onOpenLibrary: { [weak self] in
                self?.openLibrary()
            },
            onRunOCR: { [weak self] in
                self?.translateOCR()
            },
            onOpenInput: { [weak self] in
                self?.openInput()
            },
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
            },
            onOpenPrivacy: {
                SupportLinks.openPrivacy()
            },
            onShowOnboarding: { [weak self] in
                self?.presentOnboardingIfNeeded(force: true)
            }
        )
    }

    private func ensureScreenCapturePermission() -> Bool {
        guard !Permissions.hasScreenRecordingPermission() else { return true }
        panelController.showError(
            "截图 OCR 需要屏幕录制权限。打开系统设置，在“隐私与安全性 → 屏幕录制”里勾选“划词翻译”，然后重启 App。已有文字仍可用 ⌥V 剪贴板翻译。",
            actionTitle: "打开系统设置",
            onAction: {
                Permissions.openScreenRecordingSettings()
            }
        )
        return false
    }

    // MARK: - URL scheme / external entry points

    func handle(_ urls: [URL], caller: ExternalURLCallerIdentity? = nil) {
        for url in urls where url.scheme?.lowercased() == "selectiontranslator" {
            handle(url, caller: caller)
        }
    }

    private func handle(_ url: URL, caller: ExternalURLCallerIdentity?) {
        guard let command = AppURLParser.parse(url) else { return }

        guard command.requiresExternalCallerVerification else {
            if case .unknown(let action) = command {
                log.info("unknown URL action: \(action, privacy: .public)")
            }
            return
        }

        // The public scheme must not let an arbitrary app read the clipboard,
        // start a screen capture, or open an app window. Translate used to be
        // the only guarded command; every known command now passes through
        // the same caller-signature check.
        guard ExternalURLCallerVerifier.isAllowed(caller) else {
            panelController.showError(
                "无法验证外部调用来源，已拒绝。请从浏览器扩展、快捷指令或 Finder 重新调用。"
            )
            return
        }

        if case .translate(let request) = command, request.text.isEmpty {
            panelController.showError("URL 里没有 text 参数。")
            return
        }

        guard externalURLGate.accept(textLength: command.externalRateLimitCharacters) else {
            panelController.showError(
                "外部调用过于频繁，或文本超过 \(ExternalURLGate.maxTextCharacters) 字符。请稍后再试。"
            )
            return
        }

        switch command {
        case .translate(let request):
            let capture = CaptureResult(
                selectedText: String(request.text.prefix(ExternalURLGate.maxTextCharacters)),
                context: String(request.context.prefix(ExternalURLGate.maxTextCharacters)),
                appName: request.appName,
                bundleID: nil,
                windowTitle: request.title,
                source: .browser,
                documentContext: String(request.documentContext.prefix(ExternalURLGate.maxTextCharacters))
            )
            translate(capture)
        case .clipboard:
            translateClipboard()
        case .input:
            openInput()
        case .ocr:
            translateOCR()
        case .silentOCR:
            copyOCRText()
        case .library:
            openLibrary()
        case .settings:
            openSettings()
        case .unknown(let action):
            log.info("unknown URL action: \(action, privacy: .public)")
        }
    }

    // MARK: - Shared translation path

    func translate(_ capture: CaptureResult) {
        let settings = settingsStore.settings
        guard !settings.isAppExcluded(capture.bundleID) else {
            panelController.showError("已在设置里排除「\(capture.appName)」，不会在这个 App 里取词。")
            return
        }
        let localDocument = settings.useDocumentContext
            ? DocumentContextRepository.read(accountID: accountStore.activeID)
            : ""
        // Browser entries already send the page text; do not throw it away
        // when the local document is empty or disabled.
        let parts = [localDocument, capture.documentContext]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mergedDocument = parts.joined(separator: "\n\n")
        let limit = max(
            0,
            settings.documentContextMaxChars + (capture.documentContext.isEmpty ? 0 : capture.documentContext.count)
        )
        let trimmedDocument = DocumentContextTrimmer.trim(
            mergedDocument,
            maxCharacters: limit,
            selection: capture.selectedText
        )
        let enriched = capture.withDocumentContext(trimmedDocument)

        log.info("capture app=\(enriched.appName, privacy: .public) source=\(enriched.source.rawValue, privacy: .public) selectionLen=\(enriched.selectedText.count, privacy: .public) contextLen=\(enriched.context.count, privacy: .public) documentLen=\(enriched.documentContext.count, privacy: .public)")

        let apiKey = KeychainStore.read(key: "apiKey") ?? ""

        panelController.show(
            capture: enriched,
            settings: settings,
            apiKey: apiKey,
            accountID: accountStore.activeID,
            onOpenLibrary: { [weak self] in
                self?.openLibrary()
            }
        )
    }
}
