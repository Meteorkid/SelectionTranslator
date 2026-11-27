import Foundation
import Combine

struct LocalProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var avatarSymbol: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, avatarSymbol: String = "person.crop.circle.fill", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.createdAt = createdAt
    }
}

private struct LocalAccountSnapshot: Codable {
    var profiles: [LocalProfile]
    var activeID: UUID
}

@MainActor
final class LocalAccountStore: ObservableObject {
    static let avatarSymbols: [String] = [
        "person.crop.circle.fill",
        "person.crop.circle.badge.checkmark",
        "graduationcap.fill",
        "book.fill",
        "sparkles",
        "leaf.fill"
    ]

    @Published private(set) var profiles: [LocalProfile]
    @Published private(set) var activeID: UUID

    private let fileURL: URL

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelectionTranslator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        fileURL = directory.appendingPathComponent("profiles.json")

        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(LocalAccountSnapshot.self, from: data),
           !snapshot.profiles.isEmpty {
            profiles = snapshot.profiles
            activeID = snapshot.profiles.contains { $0.id == snapshot.activeID }
                ? snapshot.activeID
                : snapshot.profiles[0].id
        } else {
            let defaultName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = LocalProfile(name: defaultName.isEmpty ? "本地账户" : defaultName)
            profiles = [profile]
            activeID = profile.id
        }
        save()
    }

    var activeProfile: LocalProfile {
        profiles.first { $0.id == activeID } ?? profiles[0]
    }

    func createProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "本地账户 \(profiles.count + 1)"
        let profile = LocalProfile(
            name: trimmed.isEmpty ? fallback : trimmed,
            avatarSymbol: Self.avatarSymbols[profiles.count % Self.avatarSymbols.count]
        )
        profiles.append(profile)
        activeID = profile.id
        save()
    }

    func switchTo(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    func renameActive(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        profiles[index].name = trimmed
        save()
    }

    func setAvatar(_ symbol: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        profiles[index].avatarSymbol = symbol
        save()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        if activeID == id {
            activeID = profiles[0].id
        }
        save()
    }

    private func save() {
        let snapshot = LocalAccountSnapshot(profiles: profiles, activeID: activeID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
