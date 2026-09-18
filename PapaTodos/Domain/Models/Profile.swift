import Foundation

/// Mirrors `public.profiles`, per specification.md section 6.1.
nonisolated struct Profile: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var fullName: String?
    var avatarURL: URL?
    var personalisation: Personalisation

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case personalisation
    }

    struct Personalisation: Codable, Sendable, Equatable {
        var theme: String?
    }
}
