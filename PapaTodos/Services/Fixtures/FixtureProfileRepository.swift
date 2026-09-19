import Foundation

/// Deterministic in-memory `ProfileRepository` fake.
actor FixtureProfileRepository: ProfileRepository {
    private var profiles: [UUID: Profile]
    private var failure: DataServiceError?

    init(profiles: [Profile] = FixtureData.profiles, failure: DataServiceError? = nil) {
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        self.failure = failure
    }

    /// Test hook: makes every subsequent call throw (nil restores normal behavior).
    func setFailure(_ failure: DataServiceError?) {
        self.failure = failure
    }

    func fetchProfile(id: UUID) async throws -> Profile? {
        if let failure { throw failure }
        return profiles[id]
    }

    func fetchProfiles() async throws -> [ProfileSummary] {
        if let failure { throw failure }
        return profiles.values
            .sorted { ($0.fullName ?? "") < ($1.fullName ?? "") }
            .map { ProfileSummary(id: $0.id, fullName: $0.fullName, avatarURL: $0.avatarURL) }
    }

    func updateAvatarURL(id: UUID, to url: URL?) async throws -> Profile {
        if let failure { throw failure }
        guard var profile = profiles[id] else { throw DataServiceError.server }
        profile.avatarURL = url
        profiles[id] = profile
        return profile
    }

    func updateThemeColor(id: UUID, to hex: String) async throws -> Profile {
        if let failure { throw failure }
        guard var profile = profiles[id] else { throw DataServiceError.server }
        profile.personalisation.theme = hex
        profiles[id] = profile
        return profile
    }
}
