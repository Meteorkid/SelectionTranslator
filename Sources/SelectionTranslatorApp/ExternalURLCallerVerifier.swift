import AppKit
import Carbon
import Security

/// Identity of the process that asked LaunchServices to open the custom URL.
/// The Apple Event original-address attribute supplies a process serial number;
/// we resolve it to a live PID and then inspect that process's code signature.
struct ExternalURLCallerIdentity {
    let bundleID: String
    let pid: pid_t
    let certificateSummary: String?
    /// Set only after the live process's code requirement validates against
    /// Apple's anchor or the vendor's Developer ID team. A certificate summary
    /// alone is user-controlled data and is not proof of identity.
    let signatureValid: Bool

    init(
        bundleID: String,
        pid: pid_t,
        certificateSummary: String?,
        signatureValid: Bool
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.certificateSummary = certificateSummary
        self.signatureValid = signatureValid
    }
}

/// The custom URL scheme is a public entry point; any app can ask
/// LaunchServices to open it. This gate resolves the original sender and
/// checks both its bundle ID and its signing certificate. It is deliberately
/// a source-class check, not a cryptographic pairing; a compromised browser
/// process remains able to invoke the scheme.
enum ExternalURLCallerVerifier {
    static let allowedBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.apple.shortcuts",
        "com.apple.Automator",
        "com.apple.Terminal",
        "com.apple.finder"
    ]

    static let appleCertificates: Set<String> = [
        "Software Signing",
        "macOS Software Signing"
    ]

    static let teamCertificates: [String: String] = [
        "com.google.Chrome": "Google LLC (EQHXZ8M8AV)",
        "com.google.Chrome.canary": "Google LLC (EQHXZ8M8AV)",
        "com.microsoft.edgemac": "Microsoft Corporation (UBF8T346G9)",
        "org.mozilla.firefox": "Mozilla Corporation (43AQ936H96)"
    ]

    static func currentIdentity() -> ExternalURLCallerIdentity? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let address = event.attributeDescriptor(forKeyword: keyOriginalAddressAttr) else {
            return nil
        }

        let bundleID: String?
        let pid: pid_t

        if address.descriptorType == typeApplicationBundleID {
            bundleID = address.stringValue
            // Some LaunchServices paths (notably Shortcuts/Automator) send a
            // bundle-ID descriptor instead of a PSN. Resolve the live process
            // for that bundle ID so the certificate check still applies
            // instead of rejecting every bundle-ID-only caller.
            if let bundleID,
               let app = NSRunningApplication
                   .runningApplications(withBundleIdentifier: bundleID)
                   .first(where: { !$0.isTerminated }) {
                pid = app.processIdentifier
            } else {
                pid = 0
            }
        } else if address.descriptorType == typeProcessSerialNumber {
            pid = resolvePID(from: address)
            bundleID = runningApplication(pid: pid)?.bundleIdentifier
        } else {
            return nil
        }

        guard let bundleID, !bundleID.isEmpty else { return nil }
        let certificateSummary = pid > 0 ? signingCertificateSummary(for: pid) : nil
        let signatureValid = pid > 0 && validatesCodeRequirement(for: pid, bundleID: bundleID)
        return ExternalURLCallerIdentity(
            bundleID: bundleID,
            pid: pid,
            certificateSummary: certificateSummary,
            signatureValid: signatureValid
        )
    }

    static func isAllowed(_ identity: ExternalURLCallerIdentity?) -> Bool {
        guard let identity,
              allowedBundleIDs.contains(identity.bundleID),
              identity.signatureValid,
              let certificate = identity.certificateSummary else {
            return false
        }

        if appleCertificates.contains(certificate) {
            return true
        }
        if let expectedTeam = teamCertificates[identity.bundleID] {
            return certificate.contains(expectedTeam)
        }
        return false
    }

    private static func resolvePID(from address: NSAppleEventDescriptor) -> pid_t {
        let data = address.data
        if data.count >= 8 {
            var psn = ProcessSerialNumber()
            let bytes = [UInt8](data.prefix(8))
            psn.highLongOfPSN = uint32(from: bytes, at: 0)
            psn.lowLongOfPSN = uint32(from: bytes, at: 4)
            let pid = STProcessIDForSerialNumber(psn)
            if pid > 0 { return pid }
        }

        // Some LaunchServices paths expose a ProcessSerialNumber whose
        // process has already exited; the descriptor's diagnostic form still
        // carries the pid. Fall back to it only for a live process, which is
        // then checked against its code signature above.
        let description = address.description
        if let pidStart = description.range(of: "pid=")?.upperBound {
            let digits = description[pidStart...].prefix { $0.isNumber }
            if let pid = pid_t(digits), pid > 0,
               NSRunningApplication(processIdentifier: pid) != nil {
                return pid
            }
        }
        return 0
    }

    private static func runningApplication(pid: pid_t) -> NSRunningApplication? {
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    /// A subject-summary string can be forged by a self-signed certificate.
    /// Validate the running code against an Apple-anchored requirement and,
    /// for third-party browsers, the vendor's Developer ID team.
    private static func validatesCodeRequirement(for pid: pid_t, bundleID: String) -> Bool {
        guard let requirementString = codeRequirement(for: bundleID) else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func codeRequirement(for bundleID: String) -> String? {
        if let team = teamCertificates[bundleID] {
            guard let teamID = team.split(separator: "(").last?.dropLast() else {
                return nil
            }
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        }
        if allowedBundleIDs.contains(bundleID) {
            return "anchor apple"
        }
        return nil
    }

    private static func signingCertificateSummary(for pid: pid_t) -> String? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: 1 << 1), // kSecCSSigningInformation
            &information
        ) == errSecSuccess,
              let information,
              let certificates = (information as NSDictionary)[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else {
            return nil
        }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    private static func uint32(from bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
