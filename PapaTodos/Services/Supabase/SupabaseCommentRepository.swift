import Foundation
import PostgREST
import Supabase

nonisolated struct SupabaseCommentRepository: CommentRepository {
    let client: SupabaseClient

    private static let columns = "id, chore_id, author_id, body, created_at"

    func fetchComments(choreID: UUID) async throws -> [ChoreComment] {
        do {
            return try await client.from("chore_comments")
                .select(Self.columns)
                .eq("chore_id", value: choreID)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func addComment(choreID: UUID, body: String) async throws -> ChoreComment {
        guard let trimmed = CommentBody.validated(body) else { throw DataServiceError.server }
        do {
            // The author is the signed-in user, read from the session, never from the caller.
            let userID = try await client.auth.session.user.id
            let values: [String: AnyJSON] = [
                "chore_id": .string(choreID.uuidString.lowercased()),
                "author_id": .string(userID.uuidString.lowercased()),
                "body": .string(trimmed),
            ]
            return try await client.from("chore_comments")
                .insert(values)
                .select(Self.columns)
                .single()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// A Realtime Postgres-changes subscription scoped to one chore. The stream finishes
    /// when the connection closes; the consumer reloads and resubscribes.
    func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error> {
        AsyncThrowingStream { continuation in
            let client = self.client
            let task = Task {
                let channel = client.channel("chore-comments-\(choreID.uuidString.lowercased())")
                // Callbacks must be registered before subscribing.
                let actions = channel.postgresChange(
                    AnyAction.self, table: "chore_comments", filter: .eq("chore_id", value: choreID)
                )
                do {
                    try await channel.subscribeWithError()
                } catch {
                    await client.removeChannel(channel)
                    continuation.finish(throwing: SupabaseErrorMapper.map(error))
                    return
                }
                for await action in actions {
                    switch action {
                    case .insert(let insert):
                        if let change = RealtimeCommentMapper.inserted(record: insert.record) { continuation.yield(change) }
                    case .update(let update):
                        if let change = RealtimeCommentMapper.updated(record: update.record) { continuation.yield(change) }
                    case .delete(let delete):
                        if let change = RealtimeCommentMapper.deleted(oldRecord: delete.oldRecord) { continuation.yield(change) }
                    }
                }
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Turns the raw JSON of a Realtime event into a `CommentChange`. Rows that don't decode
/// are dropped rather than crashing the stream.
nonisolated enum RealtimeCommentMapper {
    static func inserted(record: [String: AnyJSON]) -> CommentChange? {
        decode(record).map { .inserted($0) }
    }

    static func updated(record: [String: AnyJSON]) -> CommentChange? {
        decode(record).map { .updated($0) }
    }

    /// A delete event carries only the old row's key (the table's replica identity).
    static func deleted(oldRecord: [String: AnyJSON]) -> CommentChange? {
        guard case .string(let raw)? = oldRecord["id"], let id = UUID(uuidString: raw) else { return nil }
        return .deleted(id: id)
    }

    private static func decode(_ record: [String: AnyJSON]) -> ChoreComment? {
        try? AnyJSON.object(record).decode(as: ChoreComment.self, decoder: PostgrestClient.Configuration.jsonDecoder)
    }
}
