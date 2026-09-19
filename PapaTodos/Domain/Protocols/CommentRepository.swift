import Foundation

nonisolated protocol CommentRepository: Sendable {
    func fetchComments(choreID: UUID) async throws -> [ChoreComment]
    func addComment(choreID: UUID, body: String) async throws
    func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error>
}
