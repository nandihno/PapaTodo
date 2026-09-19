import Foundation
import Supabase

/// Read-only `CommentRepository` for Phase 1. Adding comments and the Realtime
/// stream arrive in Phase 4.
nonisolated struct SupabaseCommentRepository: CommentRepository {
    let client: SupabaseClient

    func fetchComments(choreID: UUID) async throws -> [ChoreComment] {
        do {
            return try await client.from("chore_comments")
                .select("id, chore_id, author_id, body, created_at")
                .eq("chore_id", value: choreID)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func addComment(choreID: UUID, body: String) async throws {
        throw DataServiceError.notAvailableYet
    }

    func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error> {
        AsyncThrowingStream { $0.finish(throwing: DataServiceError.notAvailableYet) }
    }
}
