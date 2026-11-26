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

    private var captureTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var settingsSink: AnyCancellable?
    private var hasShownPermissionHelp = false

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

        if settingsStore.settings.checkForUpdatesOnLaunch {
            Task { @MainActor [weak self] in
                self?.checkForUpdates(manual: false)
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
            } catch OCRServiceError.cancelled {
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
            } catch OCRServiceError.cancelled {
                return
            } catch {
                self.panelController.showError("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Updates

    func checkForUpdates(manual: Bool = true) {
        let settings = settingsStore.settings
        guard !settings.updateFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if manual {
                panelController.showError(UpdateCheckerError.noFeed.localizedDescription)
            }
            return
        }

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await UpdateChecker.check(
                    feedURL: settings.updateFeedURL,
                    currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
                    currentBuild: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
                )
                switch result {
                case .available(let release):
                    self.panelController.showError(
                        "发现新版本 \(release.version)。\n\(release.notes ?? "")",
                        actionTitle: "打开下载页",
                        onAction: {
                            if let url = URL(string: release.url) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                case .upToDate:
                    if manual {
                        self.panelController.showError("当前已经是最新版本。")
                    }
                case .notConfigured:
                    if manual {
                        self.panelController.showError(UpdateCheckerError.noFeed.localizedDescription)
                    }
                }
            } catch {
                if manual {
                    self.panelController.showError("检查更新失败：\(error.localizedDescription)")
                } else {
                    self.log.info("automatic update check failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Input / library

    func openInput() {
        inputWindowController.show(
            store: settingsStore,
            accountID: accountStore.activeID,
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

    func handle(_ urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "selectiontranslator" {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard let command = AppURLParser.parse(url) else { return }
        switch command {
        case .translate(let request):
            guard !request.text.isEmpty else {
                panelController.showError("URL 里没有 text 参数。")
                return
            }
            let capture = CaptureResult(
                selectedText: request.text,
                context: request.context,
                appName: request.appName,
                bundleID: nil,
                windowTitle: request.title,
                source: .browser,
                documentContext: request.documentContext
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
        let enriched = capture.withDocumentContext(String(mergedDocument.prefix(limit)))

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
