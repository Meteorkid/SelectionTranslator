import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// AppKit sends at least one quit request while SwiftUI is still building
    /// the MenuBarExtra scene. Ignore only this short startup window; later
    /// menu, logout and Sparkle termination requests must proceed.
    private let processStartedAt = Date()

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
        let caller = ExternalURLCallerVerifier.currentIdentity()
        Task { @MainActor in
            AppState.shared?.handle(urls, caller: caller)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        OCRService.cancelActiveCaptures()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // XCTest can send a quit AppleEvent while async tests are still
        // running; keep the test host alive. During the first few seconds,
        // AppKit's scene setup may also request termination before the menu
        // bar item exists. Once the app is actually running, let menu, system
        // logout and Sparkle installation quit normally.
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if ApplicationTerminationPolicy.shouldTerminate(
            processStartedAt: processStartedAt,
            now: Date(),
            isTestHost: isTestHost
        ) {
            return .terminateNow
        }
        return .terminateCancel
    }
}
