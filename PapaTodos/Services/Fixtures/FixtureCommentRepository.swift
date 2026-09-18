import Foundation

/// Deterministic in-memory `CommentRepository` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureCommentRepository: CommentRepository {
    private var commentsByChore: [UUID: [ChoreComment]] = [:]
    private var continuations: [UUID: AsyncThrowingStream<CommentChange, Error>.Continuation] = [:]

    init() {}

    func fetchComments(choreID: UUID) async throws -> [ChoreComment] {
        commentsByChore[choreID] ?? []
    }

    func addComment(choreID: UUID, body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyBody
        }
        let comment = ChoreComment(id: UUID(), choreId: choreID, authorId: nil, body: trimmed, createdAt: Date())
        commentsByChore[choreID, default: []].append(comment)
        continuations[choreID]?.yield(.inserted(comment))
    }

    nonisolated func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.registerContinuation(continuation, for: choreID) }
        }
    }

    private func registerContinuation(
        _ continuation: AsyncThrowingStream<CommentChange, Error>.Continuation,
        for choreID: UUID
    ) {
        continuations[choreID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(for: choreID) }
        }
    }

    private func removeContinuation(for choreID: UUID) {
        continuations[choreID] = nil
    }

    enum ValidationError: Error {
        case emptyBody
    }
}
