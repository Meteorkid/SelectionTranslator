import AppKit
import SwiftUI
import os.log

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "onboarding")
    private var window: NSWindow?
    private var onComplete: (() -> Void)?
    private var didComplete = false

    func show(
        appearance: AppAppearance,
        onOpenPrivacy: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        didComplete = false

        if window == nil {
            let view = OnboardingView(
                appearance: appearance,
                onComplete: { [weak self] in self?.finish() },
                onOpenPrivacy: onOpenPrivacy
            )
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用划词翻译"
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.delegate = self
            window.center()
            self.window = window
            log.info("onboarding window created")
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        log.info("onboarding completed")
        onComplete?()
        onComplete = nil
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
