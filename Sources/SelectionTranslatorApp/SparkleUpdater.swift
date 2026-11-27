import Foundation
import Sparkle

/// Thin Sparkle wrapper. Sparkle owns the update UI, feed parsing, EdDSA
/// verification, download and installation; the menu only asks it to check.
@MainActor
final class SparkleUpdater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = SparkleUpdater()

    private var controller: SPUStandardUpdaterController!

    /// Menu-bar apps have no Dock presence; declaring gentle reminders
    /// prevents Sparkle from treating an automatic check as a disruptive
    /// background alert.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }
}
