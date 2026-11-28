import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaultsKey = "SelectionTranslator.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                settings = decoded
                // Existing 0.4.0 installs keep their current setup and should
                // not be interrupted by a first-run guide.
                OnboardingState.markCompleted()
                // Write the migrated shape back once, so future launches do
                // not keep re-inferring fields absent from the old JSON.
                save()
            } else {
                // Do not discard a malformed configuration silently; keep the
                // raw bytes under a dated backup key for manual recovery.
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                UserDefaults.standard.set(
                    data,
                    forKey: "SelectionTranslator.settings.invalid-\(formatter.string(from: Date()))"
                )
                settings = AppSettings()
                save()
            }
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
