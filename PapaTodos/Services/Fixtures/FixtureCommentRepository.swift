import Foundation

/// Deterministic in-memory `CommentRepository` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureCommentRepository: CommentRepository {
    private var commentsByChore: [UUID: [ChoreComment]]
    private var subscribers: [UUID: (choreID: UUID, continuation: AsyncThrowingStream<CommentChange, Error>.Continuation)] = [:]
    private let currentUserID: UUID
    private var failures: [DataServiceError] = []
    private var fetchFailures = 0
    private var remoteOnSubscribe: ChoreComment?

    /// - Parameter remoteCommentOnFirstSubscribe: a comment that "another client" posts about a
    ///   second after the first screen subscribes to its chore, so tests can prove a live update
    ///   arrives over the stream rather than being fetched.
    init(
        comments: [ChoreComment] = [], currentUserID: UUID = FixtureData.currentUserID,
        remoteCommentOnFirstSubscribe: ChoreComment? = nil
    ) {
        self.currentUserID = currentUserID
        self.remoteOnSubscribe = remoteCommentOnFirstSubscribe
        self.commentsByChore = Dictionary(grouping: comments, by: \.choreId)
    }

    func fetchComments(choreID: UUID) async throws -> [ChoreComment] {
        if fetchFailures > 0 {
            fetchFailures -= 1
            throw DataServiceError.offline
        }
        return (commentsByChore[choreID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(choreID: UUID, body: String) async throws -> ChoreComment {
        if !failures.isEmpty { throw failures.removeFirst() }
        guard let trimmed = CommentBody.validated(body) else { throw ValidationError.emptyBody }
        let comment = ChoreComment(id: UUID(), choreId: choreID, authorId: currentUserID, body: trimmed, createdAt: Date())
        commentsByChore[choreID, default: []].append(comment)
        broadcast(.inserted(comment), to: choreID)
        return comment
    }

    nonisolated func changes(choreID: UUID) -> AsyncThrowingStream<CommentChange, Error> {
        let id = UUID()
        return AsyncThrowingStream { continuation in
            Task { await self.register(id: id, choreID: choreID, continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister(id) }
            }
        }
    }

    // MARK: test hooks

    /// Simulates another client's change arriving over Realtime (also updates stored comments).
    func simulateRemote(_ change: CommentChange, choreID: UUID) {
        switch change {
        case .inserted(let comment), .updated(let comment):
            var list = commentsByChore[choreID, default: []]
            if let index = list.firstIndex(where: { $0.id == comment.id }) { list[index] = comment } else { list.append(comment) }
            commentsByChore[choreID] = list
        case .deleted(let id):
            commentsByChore[choreID]?.removeAll { $0.id == id }
        }
        broadcast(change, to: choreID)
    }

    /// Simulates the connection dropping: every open stream finishes (or fails).
    func dropConnections(with error: DataServiceError? = nil) {
        for subscriber in subscribers.values {
            if let error { subscriber.continuation.finish(throwing: error) } else { subscriber.continuation.finish() }
        }
        subscribers.removeAll()
    }

    /// The next `addComment` call throws this error once.
    func failNextAdd(with error: DataServiceError) { failures.append(error) }
    func failNextFetches(_ count: Int) { fetchFailures = count }

    var subscriberCount: Int { subscribers.count }
    func storedComments(for choreID: UUID) -> [ChoreComment] { commentsByChore[choreID] ?? [] }

    // MARK: internals

    private func register(id: UUID, choreID: UUID, continuation: AsyncThrowingStream<CommentChange, Error>.Continuation) {
        subscribers[id] = (choreID, continuation)
        if let remote = remoteOnSubscribe, remote.choreId == choreID {
            remoteOnSubscribe = nil
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                self.simulateRemote(.inserted(remote), choreID: choreID)
            }
        }
    }

    private func unregister(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast(_ change: CommentChange, to choreID: UUID) {
        for subscriber in subscribers.values where subscriber.choreID == choreID {
            subscriber.continuation.yield(change)
        }
    }

    enum ValidationError: Error {
        case emptyBody
    }
}
