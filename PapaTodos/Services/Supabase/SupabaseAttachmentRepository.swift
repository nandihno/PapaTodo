import Foundation
import Supabase

/// `chore_attachments` rows. Policies only let a chore's creator or assignee insert or
/// delete, so a refusal surfaces as `.notPermitted`.
nonisolated struct SupabaseAttachmentRepository: AttachmentRepository {
    let client: SupabaseClient

    private struct IDRow: Decodable { let id: UUID }

    func insert(_ attachments: [NewAttachment], choreID: UUID) async throws -> [UUID] {
        guard !attachments.isEmpty else { return [] }
        do {
            // The row owner is the authenticated user; the insert policy requires it.
            let userID = try await client.auth.session.user.id.uuidString.lowercased()
            let rows: [[String: AnyJSON]] = attachments.map { attachment in
                [
                    "chore_id": .string(choreID.uuidString.lowercased()),
                    "storage_path": .string(attachment.storagePath),
                    "public_url": .string(attachment.publicURL.absoluteString),
                    "file_name": .string(attachment.fileName),
                    "mime_type": .string(attachment.mimeType),
                    "sort_order": .integer(attachment.sortOrder),
                    "created_by": .string(userID),
                ]
            }
            let inserted: [IDRow] = try await client.from("chore_attachments")
                .insert(rows)
                .select("id")
                .execute()
                .value
            return inserted.map(\.id)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        do {
            let deleted: [IDRow] = try await client.from("chore_attachments")
                .delete()
                .in("id", values: ids.map { $0.uuidString.lowercased() })
                .select("id")
                .execute()
                .value
            // A row-level-security refusal deletes nothing and returns no error, so compare counts.
            if deleted.count != ids.count { throw DataServiceError.notPermitted }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}
