import Foundation

nonisolated protocol ChoreRepository: Sendable {
    func fetchChores() async throws -> [Chore]
    func fetchChore(id: UUID) async throws -> Chore?
    /// Creates a chore owned by the signed-in user (the creator comes from the session).
    func create(_ draft: ChoreDraft) async throws -> Chore
    /// Applies only the fields present in `patch`.
    func update(id: UUID, patch: ChorePatch) async throws -> Chore
    func updateStatus(id: UUID, status: ChoreStatus) async throws
    func delete(id: UUID) async throws
}
