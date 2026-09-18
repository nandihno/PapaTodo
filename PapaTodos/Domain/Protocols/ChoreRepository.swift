import Foundation

protocol ChoreRepository: Sendable {
    func fetchChores() async throws -> [Chore]
    func fetchChore(id: UUID) async throws -> Chore?
    func create(_ draft: ChoreDraft) async throws -> Chore
    func update(id: UUID, draft: ChoreDraft) async throws -> Chore
    func updateStatus(id: UUID, status: ChoreStatus) async throws
    func delete(id: UUID) async throws
}
