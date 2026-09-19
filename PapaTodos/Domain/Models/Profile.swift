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

    init(id: UUID, fullName: String?, avatarURL: URL?, personalisation: Personalisation) {
        self.id = id
        self.fullName = fullName
        self.avatarURL = avatarURL
        self.personalisation = personalisation
    }

    /// `personalisation` is a nullable jsonb column, so tolerate null/missing.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        personalisation = try container.decodeIfPresent(Personalisation.self, forKey: .personalisation) ?? Personalisation()
    }

    struct Personalisation: Codable, Sendable, Equatable {
        var theme: String?

        init(theme: String? = nil) {
            self.theme = theme
        }
    }
}
