import Foundation

/// Deterministic in-memory `ProfileRepository` fake.
actor FixtureProfileRepository: ProfileRepository {
    private var profiles: [Profile]

    init(profiles: [Profile] = []) {
        self.profiles = profiles
    }

    func fetchProfile(id: UUID) async throws -> Profile? {
        profiles.first { $0.id == id }
    }

    func fetchProfiles() async throws -> [ProfileSummary] {
        profiles.map { ProfileSummary(id: $0.id, fullName: $0.fullName, avatarURL: $0.avatarURL) }
    }
}
