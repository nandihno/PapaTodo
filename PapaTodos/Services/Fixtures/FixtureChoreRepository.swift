import Foundation

/// Deterministic in-memory `ChoreRepository` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureChoreRepository: ChoreRepository {
    private var chores: [UUID: Chore]
    private var failuresRemaining: Int
    private let currentUserID: UUID
    private let faults: FaultInjector

    /// - Parameter failFirstFetches: number of initial `fetchChores()` calls that throw
    ///   `.offline`, so tests can exercise error and retry states deterministically.
    init(
        chores: [Chore] = FixtureChoreRepository.sampleChores,
        failFirstFetches: Int = 0,
        currentUserID: UUID = FixtureData.currentUserID,
        faults: FaultInjector = FaultInjector()
    ) {
        self.chores = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
        self.failuresRemaining = failFirstFetches
        self.currentUserID = currentUserID
        self.faults = faults
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
        try await faults.check(.createChore)
        let now = Date()
        let chore = Chore(
            id: UUID(),
            title: draft.title,
            description: draft.description,
            assignedTo: draft.assignedTo,
            createdBy: currentUserID,
            status: draft.status,
            dueDate: draft.dueDate,
            imageURL: draft.imageURL,
            createdAt: now,
            updatedAt: now
        )
        chores[chore.id] = chore
        return chore
    }

    func update(id: UUID, patch: ChorePatch) async throws -> Chore {
        try await faults.check(.updateChore)
        guard var chore = chores[id] else { throw RepositoryError.notFound }
        if let title = patch.title { chore.title = title }
        if let description = patch.description { chore.description = description }
        if let assignedTo = patch.assignedTo { chore.assignedTo = assignedTo }
        if let status = patch.status { chore.status = status }
        if let dueDate = patch.dueDate { chore.dueDate = dueDate }
        if let imageURL = patch.imageURL { chore.imageURL = imageURL }
        chore.updatedAt = Date()
        chores[id] = chore
        return chore
    }

    func updateStatus(id: UUID, status: ChoreStatus) async throws {
        guard var chore = chores[id] else { throw RepositoryError.notFound }
        chore.status = status
        chore.updatedAt = Date()
        chores[id] = chore
    }

    func delete(id: UUID) async throws {
        try await faults.check(.deleteChore)
        guard chores.removeValue(forKey: id) != nil else { throw RepositoryError.notFound }
    }

    var allChores: [Chore] { Array(chores.values) }

    /// Test hook: adds or replaces a chore.
    func store(_ chore: Chore) { chores[chore.id] = chore }

    enum RepositoryError: Error {
        case notFound
    }
}

extension FixtureChoreRepository {
    static var sampleChores: [Chore] { FixtureData.chores() }
}
