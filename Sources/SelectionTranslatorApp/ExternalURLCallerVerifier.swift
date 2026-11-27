import AppKit
import Carbon

/// The custom URL scheme is a public entry point; any app can ask
/// LaunchServices to open it. macOS records the sender as the original
/// address of the Apple event, so this gate resolves that process to a bundle
/// ID and only accepts known browser, Shortcuts, Terminal, and automation
/// callers. This is a source-class check, not a cryptographic pairing; a
/// compromised browser process remains able to invoke the scheme.
enum ExternalURLCallerVerifier {
    static let allowedBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "com.apple.shortcuts",
        "com.apple.Automator",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.finder"
    ]

    static func currentBundleID() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let address = event.attributeDescriptor(forKeyword: keyOriginalAddressAttr) else {
            return nil
        }

        if address.descriptorType == typeApplicationBundleID {
            return address.stringValue
        }

        if address.descriptorType == typeProcessSerialNumber {
            let data = address.data
            if data.count >= 8 {
                var psn = ProcessSerialNumber()
                let bytes = [UInt8](data.prefix(8))
                psn.highLongOfPSN = Self.uint32(from: bytes, at: 0)
                psn.lowLongOfPSN = Self.uint32(from: bytes, at: 4)
                let pid = STProcessIDForSerialNumber(psn)
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    return app.bundleIdentifier
                }
            }
        }

        // Some LaunchServices paths expose a ProcessSerialNumber whose
        // process has already exited; the descriptor's diagnostic form still
        // carries the pid. Fall back to it only for a live process.
        let description = address.description
        if let pidStart = description.range(of: "pid=")?.upperBound {
            let digits = description[pidStart...].prefix { $0.isNumber }
            if let pid = pid_t(digits), pid > 0,
               let app = NSRunningApplication(processIdentifier: pid) {
                return app.bundleIdentifier
            }
        }
        return nil
    }

    static func isAllowed(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return allowedBundleIDs.contains(bundleID)
    }

    private static func uint32(from bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
