import Foundation

nonisolated protocol ProfileRepository: Sendable {
    func fetchProfile(id: UUID) async throws -> Profile?
    func fetchProfiles() async throws -> [ProfileSummary]

    /// Sets (or clears, with nil) the avatar URL on the given user's own profile row.
    func updateAvatarURL(id: UUID, to url: URL?) async throws -> Profile
    /// Sets the theme color (`#RRGGBB`) on the given user's own profile row, keeping
    /// any other keys already stored in `personalisation`.
    func updateThemeColor(id: UUID, to hex: String) async throws -> Profile
}
