import AppKit
import SwiftUI
import os.log

@MainActor
final class TranslationPanelController {
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "panel")
    private var panel: TranslationPanel?
    private var model: TranslationViewModel?

    /// AppState owns the settings store; the panel is created outside SwiftUI,
    /// so it asks for the current appearance each time a panel is shown.
    var appearanceProvider: () -> AppAppearance = { .native }

    func show(
        capture: CaptureResult,
        settings: AppSettings,
        apiKey: String,
        accountID: UUID,
        onOpenLibrary: @escaping () -> Void
    ) {
        hide()

        let viewModel = TranslationViewModel()
        let appearance = appearanceProvider()
        let view = TranslationPanelView(
            model: viewModel,
            onClose: { [weak self] in
                self?.hide()
            },
            onOpenLibrary: onOpenLibrary
        )
        .stAppearance(appearance)
        let panel = makePanel(rootView: view, width: 480, height: 420)
        self.panel = panel
        self.model = viewModel

        position(panel)
        panel.orderFrontRegardless()
        log.info("translation panel shown")
        viewModel.start(
            capture: capture,
            settings: settings,
            apiKey: apiKey,
            accountID: accountID
        )
    }

    func showError(
        _ message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        log.info("showError: \(message, privacy: .public)")
        hide()

        let view = ErrorPanelView(
            message: message,
            actionTitle: actionTitle,
            onAction: onAction,
            onClose: { [weak self] in
                self?.hide()
            },
            height: actionTitle == nil ? 190 : 240
        )
        .stAppearance(appearanceProvider())
        let panel = makePanel(rootView: view, width: 480, height: actionTitle == nil ? 190 : 240)
        self.panel = panel

        position(panel)
        panel.orderFrontRegardless()
    }

    func showPermissionHelp(
        onOpenSettings: @escaping () -> Void,
        onUseClipboard: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        hide()

        let view = PermissionPanelView(
            onOpenSettings: onOpenSettings,
            onUseClipboard: onUseClipboard,
            onClose: onClose
        )
        .stAppearance(appearanceProvider())
        let panel = makePanel(rootView: view, width: 480, height: 250)
        self.panel = panel

        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        model?.cancel()
        model = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel<Content: View>(
        rootView: Content,
        width: CGFloat,
        height: CGFloat
    ) -> TranslationPanel {
        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = STTheme.panelRadius
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = panel.frame.size

        var origin = NSPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }
}
