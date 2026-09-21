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
        do {
            // The creator is the authenticated user, read from the session, never from the caller.
            let userID = try await client.auth.session.user.id
            var values: [String: AnyJSON] = [
                "title": .string(draft.title),
                "description": Self.json(draft.description),
                "assigned_to": Self.json(draft.assignedTo),
                "status": .string(draft.status.rawValue),
                "due_date": Self.json(draft.dueDate),
                "image_url": Self.json(draft.imageURL),
            ]
            values["created_by"] = .string(userID.uuidString.lowercased())
            return try await client.from("chores")
                .insert(values)
                .select(Self.select)
                .single()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func update(id: UUID, patch: ChorePatch) async throws -> Chore {
        guard !patch.isEmpty else {
            guard let current = try await fetchChore(id: id) else { throw DataServiceError.server }
            return current
        }
        do {
            var values: [String: AnyJSON] = [:]
            if let title = patch.title { values["title"] = .string(title) }
            if let description = patch.description { values["description"] = Self.json(description) }
            if let assignedTo = patch.assignedTo { values["assigned_to"] = Self.json(assignedTo) }
            if let status = patch.status { values["status"] = .string(status.rawValue) }
            if let dueDate = patch.dueDate { values["due_date"] = Self.json(dueDate) }
            if let imageURL = patch.imageURL { values["image_url"] = Self.json(imageURL) }
            // Never sends created_by, and updated_at is maintained by a database trigger.
            let rows: [Chore] = try await client.from("chores")
                .update(values)
                .eq("id", value: id)
                .select(Self.select)
                .execute()
                .value
            guard let chore = rows.first else { throw DataServiceError.server }
            return chore
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Sets only the status; `updated_at` is maintained by a database trigger. Zero rows
    /// changed means the chore is gone (or the write was refused), which is a failure.
    func updateStatus(id: UUID, status: ChoreStatus) async throws {
        struct IDRow: Decodable { let id: UUID }
        do {
            let rows: [IDRow] = try await client.from("chores")
                .update(["status": AnyJSON.string(status.rawValue)])
                .eq("id", value: id)
                .select("id")
                .execute()
                .value
            guard !rows.isEmpty else { throw DataServiceError.server }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Deletes the chore row; its comments and attachment rows are removed by the foreign
    /// keys' `ON DELETE CASCADE`. Deleting an already-missing chore is not an error.
    ///
    /// Only the creator may delete a chore. When row-level security refuses, PostgREST reports success
    /// with zero rows rather than an error, so an empty result is checked against whether the chore is
    /// still there: still there means the delete was refused.
    func delete(id: UUID) async throws {
        do {
            let deleted: [DeletedRow] = try await client.from("chores")
                .delete()
                .eq("id", value: id)
                .select("id")
                .execute()
                .value
            if deleted.isEmpty, try await fetchChore(id: id) != nil { throw DataServiceError.notCreator }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    private struct DeletedRow: Decodable { let id: UUID }

    // MARK: JSON helpers

    static func json(_ value: String?) -> AnyJSON { value.map { .string($0) } ?? .null }
    static func json(_ value: UUID?) -> AnyJSON { value.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func json(_ value: URL?) -> AnyJSON { value.map { .string($0.absoluteString) } ?? .null }
    static func json(_ value: Date?) -> AnyJSON {
        guard let value else { return .null }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .string(formatter.string(from: value))
    }
}
