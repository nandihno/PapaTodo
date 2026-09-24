import Foundation

/// Reads and writes the shared favourite chores.
nonisolated protocol ChoreTemplateRepository: Sendable {
    /// Every favourite in the shared order (`sort_order`, then oldest first).
    func fetchTemplates() async throws -> [ChoreTemplate]
    /// Throws `.duplicate` when a favourite with the same title (ignoring case and spaces) exists.
    func create(_ draft: ChoreTemplateDraft, sortOrder: Int) async throws -> ChoreTemplate
    /// Throws `.notFound` when the favourite was deleted in the meantime.
    func update(id: UUID, with draft: ChoreTemplateDraft) async throws -> ChoreTemplate
    /// Deleting a favourite that is already gone is not an error.
    func delete(id: UUID) async throws
    /// Writes new positions for only the favourites whose position changed.
    func updateSortOrders(_ orders: [UUID: Int]) async throws
}
