import Foundation

/// Mirrors `public.chores`, per specification.md section 6.2.
nonisolated struct Chore: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var assignedTo: UUID?
    var createdBy: UUID?
    var status: ChoreStatus
    /// Uses the local-noon sentinel for date-only chores; see DueDateRule.
    var dueDate: Date?
    var imageURL: URL?
    let createdAt: Date
    var updatedAt: Date
    /// Embedded by the relational select (`assignedProfile:profiles!chores_assigned_to_fkey`).
    var assignedProfile: ProfileSummary?
    var createdProfile: ProfileSummary?
    /// Embedded `chore_attachments`; nil when the select didn't request them.
    var attachments: [ChoreAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case assignedTo = "assigned_to"
        case createdBy = "created_by"
        case dueDate = "due_date"
        case imageURL = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case assignedProfile, createdProfile, attachments
    }
}

/// Fields needed to create or update a chore, per the `ChoreRepository` protocol.
nonisolated struct ChoreDraft: Sendable {
    var title: String
    var description: String?
    var assignedTo: UUID?
    var status: ChoreStatus
    var dueDate: Date?
}
