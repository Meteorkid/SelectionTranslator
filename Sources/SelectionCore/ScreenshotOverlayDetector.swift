import AppKit
import CoreGraphics

/// Detects a screenshot tool's capture overlay before simulating ⌘C.
///
/// A fullscreen capture overlay can interpret a synthetic ⌘C as its own
/// "copy capture" command and cancel the user's selection. MoePeek's detector
/// is the reference for this behavior; this version uses CoreGraphics display
/// bounds and keeps the policy independent of any capture tool API.
enum ScreenshotOverlayDetector {
    private static let captureToolBundleIDs: Set<String> = [
        "pl.maketheweb.cleanshotx",
        "com.apple.screencaptureui",
        "cc.ffitch.shottr",
        "so.cap.desktop",
        "com.zzd.xnip",
        "com.snipaste"
    ]

    private static let displayCoverageThreshold: CGFloat = 0.9

    static func isCapturingScreenshot() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return false
        }
        let displays = activeDisplayBounds()
        guard !displays.isEmpty else { return false }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  coversWholeDisplay(bounds, displays),
                  let pidValue = window[kCGWindowOwnerPID as String] as? Int,
                  let pid = pid_t(exactly: pidValue) else {
                continue
            }

            if let frontmostPID, pid == frontmostPID {
                return true
            }
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
               captureToolBundleIDs.contains(bundleID.lowercased()) {
                return true
            }
        }
        return false
    }

    static func coversWholeDisplay(_ rect: CGRect, _ displays: [CGRect]) -> Bool {
        displays.contains { display in
            guard display.width > 0, display.height > 0 else { return false }
            let overlap = display.intersection(rect)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height
                >= display.width * display.height * displayCoverageThreshold
        }
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}
