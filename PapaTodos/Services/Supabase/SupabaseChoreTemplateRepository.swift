import Foundation
import Supabase

/// `public.chore_templates`. Row-level security lets any signed-in family member read and write
/// every favourite; `created_by` defaults to the session user in the database and is never sent.
nonisolated struct SupabaseChoreTemplateRepository: ChoreTemplateRepository {
    let client: SupabaseClient

    private static let table = "chore_templates"
    private static let columns = "id, title, description, assigned_to, sort_order, created_by"

    func fetchTemplates() async throws -> [ChoreTemplate] {
        do {
            return try await client.from(Self.table)
                .select(Self.columns)
                .order("sort_order")
                .order("created_at")
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func create(_ draft: ChoreTemplateDraft, sortOrder: Int) async throws -> ChoreTemplate {
        var values = Self.values(for: draft)
        values["sort_order"] = .integer(sortOrder)
        do {
            return try await client.from(Self.table)
                .insert(values)
                .select(Self.columns)
                .single()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func update(id: UUID, with draft: ChoreTemplateDraft) async throws -> ChoreTemplate {
        do {
            let rows: [ChoreTemplate] = try await client.from(Self.table)
                .update(Self.values(for: draft))
                .eq("id", value: id)
                .select(Self.columns)
                .execute()
                .value
            guard let template = rows.first else { throw DataServiceError.notFound }
            return template
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func delete(id: UUID) async throws {
        do {
            try await client.from(Self.table).delete().eq("id", value: id).execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// One small update per moved row. A row deleted meanwhile simply matches nothing.
    func updateSortOrders(_ orders: [UUID: Int]) async throws {
        do {
            for (id, order) in orders.sorted(by: { $0.value < $1.value }) {
                try await client.from(Self.table)
                    .update(["sort_order": AnyJSON.integer(order)])
                    .eq("id", value: id)
                    .execute()
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    private static func values(for draft: ChoreTemplateDraft) -> [String: AnyJSON] {
        [
            "title": .string(draft.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "description": SupabaseChoreRepository.json(draft.description),
            "assigned_to": SupabaseChoreRepository.json(draft.assignedTo),
        ]
    }
}
