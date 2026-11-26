import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum SelectionCaptureService {
    private static let blockedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.KeychainAccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop"
    ]

    static func capture(maxContextLength: Int, useClipboardFallback: Bool) async -> CaptureResult? {
        let app = NSWorkspace.shared.frontmostApplication
        AX.prepareAccessibility(for: app)

        if let result = accessibilityCapture(maxContextLength: maxContextLength) {
            return result
        }

        guard useClipboardFallback,
              let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier
        let targetPID = app.processIdentifier

        return await Task.detached(priority: .userInitiated) {
            guard !IsSecureEventInputEnabled(),
                  let selected = ClipboardFallback.copySelection(targetPID: targetPID),
                  !selected.isEmpty else {
                return nil
            }
            return CaptureResult(
                selectedText: selected,
                context: "",
                appName: appName,
                bundleID: bundleID,
                windowTitle: nil,
                source: .clipboard
            )
        }.value
    }

    static func prepareAccessibility(for app: NSRunningApplication?) {
        AX.prepareAccessibility(for: app)
    }

    static func accessibilityCapture(maxContextLength: Int) -> CaptureResult? {
        guard !IsSecureEventInputEnabled() else { return nil }

        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        if let bundleID, blockedBundleIDs.contains(bundleID) {
            return nil
        }

        AX.prepareAccessibility(for: app)

        guard let element = AX.focusedElement(),
              !AX.isSecureTextField(element),
              let selected = AX.selectedText(of: element),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let range = AX.selectedRange(of: element)
        let context = range.map {
            ContextExtractor.context(around: $0, in: element, maxLength: maxContextLength)
        } ?? ""

        return CaptureResult(
            selectedText: selected,
            context: context,
            appName: app?.localizedName ?? "Unknown",
            bundleID: bundleID,
            windowTitle: AX.windowTitle(of: element),
            source: .accessibility
        )
    }
}
