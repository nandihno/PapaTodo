import Foundation

/// Attachment ordering and legacy fallback, ported from `getChoreAttachments` /
/// `getPrimaryAttachment` in PapaBoard's `src/lib/attachments.js`.
nonisolated enum ChoreAttachments {
    /// Attachment rows sorted by `sort_order`, then `created_at`, then id. Chores that
    /// only have the legacy `image_url` get one synthesized attachment.
    static func all(for chore: Chore) -> [ChoreAttachment] {
        if let attachments = chore.attachments, !attachments.isEmpty {
            return attachments.sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        guard let imageURL = chore.imageURL else { return [] }
        return [
            ChoreAttachment(
                id: chore.id, choreId: chore.id, storagePath: "", publicURL: imageURL,
                fileName: "photo attachment", mimeType: "image/*", sortOrder: 0,
                createdBy: chore.createdBy, createdAt: chore.createdAt
            )
        ]
    }

    static func primary(for chore: Chore) -> ChoreAttachment? {
        all(for: chore).first
    }
}
