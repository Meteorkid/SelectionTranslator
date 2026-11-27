import Foundation

/// One-time first-run guide. This is deliberately separate from `AppSettings`
/// so existing installs can be marked as already-onboarded during migration.
enum OnboardingState {
    static let completedKey = "SelectionTranslator.onboardingCompleted.v1"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedKey)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
        defaults.synchronize()
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
        defaults.synchronize()
    }
}
