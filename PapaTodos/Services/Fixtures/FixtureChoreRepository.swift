import Foundation

/// Deterministic in-memory `ChoreRepository` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureChoreRepository: ChoreRepository {
    private var chores: [UUID: Chore]

    init(chores: [Chore] = FixtureChoreRepository.sampleChores) {
        self.chores = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
    }

    func fetchChores() async throws -> [Chore] {
        Array(chores.values)
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
    /// A small, realistic fixture set spanning every DueTone/sort-rank case:
    /// overdue, due today (timed and date-only), future, no due date, and done.
    static let sampleChores: [Chore] = {
        let calendar = Calendar.current
        let now = Date()

        func offsetDays(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: now)!
        }

        return [
            Chore(
                id: UUID(), title: "Take out recycling",
                description: "Bins go out Tuesday night.",
                assignedTo: nil, createdBy: nil, status: .pending,
                dueDate: DueDateRule.dateOnlyTimestamp(
                    year: calendar.component(.year, from: offsetDays(-2)),
                    month: calendar.component(.month, from: offsetDays(-2)),
                    day: calendar.component(.day, from: offsetDays(-2))
                ),
                imageURL: nil, createdAt: offsetDays(-5), updatedAt: offsetDays(-5)
            ),
            Chore(
                id: UUID(), title: "Vacuum lounge room",
                description: nil,
                assignedTo: nil, createdBy: nil, status: .pending,
                dueDate: DueDateRule.dateOnlyTimestamp(
                    year: calendar.component(.year, from: now),
                    month: calendar.component(.month, from: now),
                    day: calendar.component(.day, from: now)
                ),
                imageURL: nil, createdAt: offsetDays(-1), updatedAt: offsetDays(-1)
            ),
            Chore(
                id: UUID(), title: "Water the garden",
                description: nil,
                assignedTo: nil, createdBy: nil, status: .pending,
                dueDate: offsetDays(3),
                imageURL: nil, createdAt: offsetDays(-3), updatedAt: offsetDays(-3)
            ),
            Chore(
                id: UUID(), title: "Sort the pantry",
                description: nil,
                assignedTo: nil, createdBy: nil, status: .pending,
                dueDate: nil,
                imageURL: nil, createdAt: offsetDays(-4), updatedAt: offsetDays(-4)
            ),
            Chore(
                id: UUID(), title: "Fold laundry",
                description: nil,
                assignedTo: nil, createdBy: nil, status: .done,
                dueDate: offsetDays(-1),
                imageURL: nil, createdAt: offsetDays(-2), updatedAt: offsetDays(-1)
            ),
        ]
    }()
}
