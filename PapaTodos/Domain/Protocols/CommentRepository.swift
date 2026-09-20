import Foundation

nonisolated protocol CommentRepository: Sendable {
    /// Comments for a chore, oldest first.
    func fetchComments(choreID: UUID) async throws -> [ChoreComment]
    /// Adds a comment as the signed-in user and returns the stored row.
    func addComment(choreID: UUID, body: String) async throws -> ChoreComment
    /// Live changes to this chore's comments. Ends (normally or with an error) when the
    /// connection drops, so the caller can reload and resubscribe; cancelling the consuming
    /// task closes the subscription.
    func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error>
}
