import Foundation
import Supabase

/// Read-only `ChoreRepository` for Phase 1. Writes belong to Phase 3 and throw
/// `.notAvailableYet` so nothing can mutate family data before then.
///
/// The select mirrors PapaBoard's `choreSelectWithAttachments`
/// (`src/lib/chores.js`). The FK names it relies on were confirmed against the
/// live schema on 2026-09-19, so no separate fallback query is needed.
nonisolated struct SupabaseChoreRepository: ChoreRepository {
    let client: SupabaseClient

    private static let select = """
        id, title, description, assigned_to, created_by, status, due_date, image_url, created_at, updated_at,
        assignedProfile:profiles!chores_assigned_to_fkey(id, full_name, avatar_url),
        createdProfile:profiles!chores_created_by_fkey(id, full_name, avatar_url),
        attachments:chore_attachments(id, chore_id, storage_path, public_url, file_name, mime_type, sort_order, created_by, created_at)
        """

    func fetchChores() async throws -> [Chore] {
        do {
            return try await client.from("chores").select(Self.select).execute().value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func fetchChore(id: UUID) async throws -> Chore? {
        do {
            let rows: [Chore] = try await client.from("chores")
                .select(Self.select)
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func create(_ draft: ChoreDraft) async throws -> Chore {
        throw DataServiceError.notAvailableYet
    }

    func update(id: UUID, draft: ChoreDraft) async throws -> Chore {
        throw DataServiceError.notAvailableYet
    }

    func updateStatus(id: UUID, status: ChoreStatus) async throws {
        throw DataServiceError.notAvailableYet
    }

    func delete(id: UUID) async throws {
        throw DataServiceError.notAvailableYet
    }
}
