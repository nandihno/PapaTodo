import Foundation

/// Mirrors `public.chore_attachments`, per specification.md section 6.4.
nonisolated struct ChoreAttachment: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let choreId: UUID
    var storagePath: String
    var publicURL: URL
    var fileName: String?
    var mimeType: String?
    var sortOrder: Int
    var createdBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case choreId = "chore_id"
        case storagePath = "storage_path"
        case publicURL = "public_url"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case sortOrder = "sort_order"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}
