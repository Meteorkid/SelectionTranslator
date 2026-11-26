import AppKit
import ApplicationServices

@MainActor
enum SelectionCaptureService {
    private static let blockedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.KeychainAccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop"
    ]

    static func capture(maxContextLength: Int, useClipboardFallback: Bool) async -> CaptureResult? {
        if let result = accessibilityCapture(maxContextLength: maxContextLength) {
            return result
        }

        guard useClipboardFallback else { return nil }

        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier

        return await Task.detached(priority: .userInitiated) {
            guard let selected = ClipboardFallback.copySelection(), !selected.isEmpty else {
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

    static func accessibilityCapture(maxContextLength: Int) -> CaptureResult? {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        if let bundleID, blockedBundleIDs.contains(bundleID) {
            return nil
        }

        guard let element = AX.focusedElement() else { return nil }
        guard let selected = AX.selectedText(of: element), !selected.isEmpty else { return nil }

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
