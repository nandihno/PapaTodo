import Foundation

/// Deterministic in-memory `ChoreTemplateRepository` fake with the database's unique-title rule.
actor FixtureChoreTemplateRepository: ChoreTemplateRepository {
    private var templates: [ChoreTemplate]
    private var failure: DataServiceError?
    /// Every call to `updateSortOrders`, for tests.
    private(set) var sortOrderWrites: [[UUID: Int]] = []

    init(templates: [ChoreTemplate] = FixtureData.templates, failure: DataServiceError? = nil) {
        self.templates = templates
        self.failure = failure
    }

    /// Test hook: makes every subsequent call throw (nil restores normal behavior).
    func setFailure(_ failure: DataServiceError?) {
        self.failure = failure
    }

    /// Test hook: another device removes a favourite.
    func removeRemotely(id: UUID) {
        templates.removeAll { $0.id == id }
    }

    func fetchTemplates() async throws -> [ChoreTemplate] {
        if let failure { throw failure }
        return templates.sorted { $0.sortOrder < $1.sortOrder }
    }

    func create(_ draft: ChoreTemplateDraft, sortOrder: Int) async throws -> ChoreTemplate {
        if let failure { throw failure }
        guard !templates.contains(where: { FavouriteRules.sameTitle($0.title, draft.title) }) else {
            throw DataServiceError.duplicate
        }
        let template = ChoreTemplate(
            id: UUID(), title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description, assignedTo: draft.assignedTo,
            sortOrder: sortOrder, createdBy: FixtureData.currentUserID
        )
        templates.append(template)
        return template
    }

    func update(id: UUID, with draft: ChoreTemplateDraft) async throws -> ChoreTemplate {
        if let failure { throw failure }
        guard let index = templates.firstIndex(where: { $0.id == id }) else { throw DataServiceError.notFound }
        guard !templates.contains(where: { $0.id != id && FavouriteRules.sameTitle($0.title, draft.title) }) else {
            throw DataServiceError.duplicate
        }
        templates[index].title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        templates[index].description = draft.description
        templates[index].assignedTo = draft.assignedTo
        return templates[index]
    }

    func delete(id: UUID) async throws {
        if let failure { throw failure }
        templates.removeAll { $0.id == id }
    }

    func updateSortOrders(_ orders: [UUID: Int]) async throws {
        if let failure { throw failure }
        sortOrderWrites.append(orders)
        for (id, order) in orders {
            if let index = templates.firstIndex(where: { $0.id == id }) { templates[index].sortOrder = order }
        }
    }
}
