import Foundation

/// Keeps the rules for accepting an AppKit termination request in one testable
/// place. Sparkle, the menu and system logout all go through this policy.
enum ApplicationTerminationPolicy {
    static let startupGrace: TimeInterval = 3

    static func shouldTerminate(
        processStartedAt: Date,
        now: Date,
        isTestHost: Bool
    ) -> Bool {
        // XCTest can send a quit AppleEvent while async tests are still running.
        if isTestHost {
            return false
        }
        return now.timeIntervalSince(processStartedAt) >= startupGrace
    }
}
