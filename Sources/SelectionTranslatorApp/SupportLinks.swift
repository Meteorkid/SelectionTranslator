import AppKit

enum SupportLinks {
    static let privacy = URL(string: "https://github.com/Meteorkid/SelectionTranslator/blob/main/PRIVACY.md")!
    static let issues = URL(string: "https://github.com/Meteorkid/SelectionTranslator/issues")!

    static func openPrivacy() {
        NSWorkspace.shared.open(privacy)
    }

    static func openIssues() {
        NSWorkspace.shared.open(issues)
    }
}
