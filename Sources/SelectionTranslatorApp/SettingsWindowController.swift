import AppKit
import SwiftUI
import os.log

@MainActor
final class SettingsWindowController {
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "settings")
    private var window: NSWindow?

    func show(
        store: SettingsStore,
        accountStore: LocalAccountStore,
        onOpenLibrary: @escaping () -> Void,
        onRunOCR: @escaping () -> Void,
        onOpenInput: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void,
        onShowOnboarding: @escaping () -> Void
    ) {
        log.info("show settings requested")
        if window == nil {
            let view = SettingsView(
                store: store,
                accountStore: accountStore,
                onOpenLibrary: onOpenLibrary,
                onRunOCR: onRunOCR,
                onOpenInput: onOpenInput,
                onCheckForUpdates: onCheckForUpdates,
                onOpenPrivacy: onOpenPrivacy,
                onShowOnboarding: onShowOnboarding
            )
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 800),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.center()
            self.window = window
            log.info("settings window created")
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        log.info("settings window ordered front visible=\(self.window?.isVisible ?? false, privacy: .public)")
    }
}
