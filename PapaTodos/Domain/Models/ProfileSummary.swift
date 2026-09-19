import Foundation

/// The embedded profile shape returned by PapaBoard's relational selects
/// (`assignedProfile` / `createdProfile`): `id, full_name, avatar_url` only.
nonisolated struct ProfileSummary: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var fullName: String?
    var avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}
