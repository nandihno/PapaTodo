import Foundation

/// Deterministic in-memory `ChoreRepository` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureChoreRepository: ChoreRepository {
    private var chores: [UUID: Chore]
    private var failuresRemaining: Int

    /// - Parameter failFirstFetches: number of initial `fetchChores()` calls that throw
    ///   `.offline`, so tests can exercise error and retry states deterministically.
    init(chores: [Chore] = FixtureChoreRepository.sampleChores, failFirstFetches: Int = 0) {
        self.chores = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
        self.failuresRemaining = failFirstFetches
    }

    func fetchChores() async throws -> [Chore] {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw DataServiceError.offline
        }
        return Array(chores.values)
    }

    func fetchChore(id: UUID) async throws -> Chore? {
        chores[id]
    }

    func create(_ draft: ChoreDraft) async throws -> Chore {
        let now = Date()
        let chore = Chore(
            id: UUID(),
            title: draft.title,
            description: draft.description,
            assignedTo: draft.assignedTo,
            createdBy: nil,
            status: draft.status,
            dueDate: draft.dueDate,
            imageURL: nil,
            createdAt: now,
            updatedAt: now
        )
        chores[chore.id] = chore
        return chore
    }

    func update(id: UUID, draft: ChoreDraft) async throws -> Chore {
        guard var chore = chores[id] else {
            throw RepositoryError.notFound
        }
        chore.title = draft.title
        chore.description = draft.description
        chore.assignedTo = draft.assignedTo
        chore.status = draft.status
        chore.dueDate = draft.dueDate
        chore.updatedAt = Date()
        chores[id] = chore
        return chore
    }

    func updateStatus(id: UUID, status: ChoreStatus) async throws {
        guard var chore = chores[id] else {
            throw RepositoryError.notFound
        }
        chore.status = status
        chore.updatedAt = Date()
        chores[id] = chore
    }

    func delete(id: UUID) async throws {
        guard chores.removeValue(forKey: id) != nil else {
            throw RepositoryError.notFound
        }
    }

    enum RepositoryError: Error {
        case notFound
    }
}

extension FixtureChoreRepository {
    static var sampleChores: [Chore] { FixtureData.chores() }
}
