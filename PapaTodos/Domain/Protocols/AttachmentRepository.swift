import Foundation

/// `chore_attachments` rows. Row-level security only lets a chore's creator or assignee
/// add or remove them, so these can fail with `.notPermitted` on someone else's chore.
nonisolated protocol AttachmentRepository: Sendable {
    /// Inserts rows for `choreID`, owned by the signed-in user. Returns the new row ids.
    func insert(_ attachments: [NewAttachment], choreID: UUID) async throws -> [UUID]
    func delete(ids: [UUID]) async throws
}

/// The `chore-images` Storage bucket.
nonisolated protocol AttachmentStorage: Sendable {
    /// Uploads under the signed-in user's own prefix: `{userId}/{timestamp}-{uuid}-{filename}`.
    func upload(_ photo: PhotoUpload) async throws -> UploadedFile
    /// Removes objects and returns the paths that were **actually** removed. Storage
    /// policies can silently refuse a delete, so callers must compare against what they asked for.
    func remove(paths: [String]) async throws -> [String]
}
