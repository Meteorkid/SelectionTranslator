import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var allowQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar translator must stay running")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppState.shared?.handle(urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.allowQuit ? .terminateNow : .terminateCancel
    }
}
