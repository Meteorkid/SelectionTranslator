import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaultsKey = "SelectionTranslator.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
            // Existing 0.4.0 installs keep their current setup and should not
            // be interrupted by a first-run guide.
            OnboardingState.markCompleted()
            // Write the migrated shape back once, so future launches do not
            // keep re-inferring fields that were absent from the old JSON.
            save()
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
