import Foundation

/// A favourite chore: a shared template that pre-fills the New Chore form. Mirrors
/// `public.chore_templates` (docs/phase-7-favourites-plan.md). Anyone in the family may edit it.
nonisolated struct ChoreTemplate: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    /// Plain text or sanitised HTML, stored exactly like `chores.description`.
    var description: String?
    var assignedTo: UUID?
    var sortOrder: Int
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case assignedTo = "assigned_to"
        case sortOrder = "sort_order"
        case createdBy = "created_by"
    }
}

/// The editable fields of a favourite.
nonisolated struct ChoreTemplateDraft: Sendable, Equatable {
    var title: String
    var description: String?
    var assignedTo: UUID?
}

extension ChoreTemplateDraft {
    /// A favourite made from an existing chore: its title, its description exactly as stored,
    /// and its assignee.
    nonisolated init(chore: Chore) {
        self.init(title: chore.title, description: chore.description, assignedTo: chore.assignedTo)
    }
}
