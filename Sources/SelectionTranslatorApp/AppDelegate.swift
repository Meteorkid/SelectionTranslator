import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar translator must stay running")

        // Fresh installs see the three promises before Sparkle's first
        // automatic check; existing installs start the updater immediately.
        let environment = ProcessInfo.processInfo.environment
        let showingOnboarding = environment["ST_SKIP_ONBOARDING"] == "1"
            ? false
            : (AppState.shared?.presentOnboardingIfNeeded() ?? false)
        if !showingOnboarding {
            AppState.shared?.startUpdater()
        }

        if environment["ST_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                AppState.shared?.openSettings()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let callerBundleID = ExternalURLCallerVerifier.currentBundleID()
        Task { @MainActor in
            AppState.shared?.handle(urls, callerBundleID: callerBundleID)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.allowQuit ? .terminateNow : .terminateCancel
    }
}
