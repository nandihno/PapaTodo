import Foundation

/// Mirrors `public.chore_comments`, per specification.md section 6.5.
nonisolated struct ChoreComment: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let choreId: UUID
    var authorId: UUID?
    var body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case choreId = "chore_id"
        case authorId = "author_id"
        case createdAt = "created_at"
    }
}

/// A single change delivered by `CommentRepository.changes(choreID:)`.
nonisolated enum CommentChange: Sendable, Equatable {
    case inserted(ChoreComment)
    case updated(ChoreComment)
    case deleted(id: UUID)
}
