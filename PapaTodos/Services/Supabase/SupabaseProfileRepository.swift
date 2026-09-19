import Foundation
import Supabase

nonisolated struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    private static let columns = "id, full_name, avatar_url, personalisation"

    func fetchProfile(id: UUID) async throws -> Profile? {
        do {
            let rows: [Profile] = try await client.from("profiles")
                .select(Self.columns)
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func fetchProfiles() async throws -> [ProfileSummary] {
        do {
            return try await client.from("profiles")
                .select("id, full_name, avatar_url")
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func updateAvatarURL(id: UUID, to url: URL?) async throws -> Profile {
        let value: AnyJSON = url.map { .string($0.absoluteString) } ?? .null
        return try await update(id: id, values: ["avatar_url": value])
    }

    func updateThemeColor(id: UUID, to hex: String) async throws -> Profile {
        struct PersonalisationRow: Decodable { let personalisation: AnyJSON? }
        do {
            // Merge into the stored object so unknown keys survive, like the web app.
            let rows: [PersonalisationRow] = try await client.from("profiles")
                .select("personalisation")
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            var personalisation = rows.first?.personalisation?.objectValue ?? [:]
            personalisation["theme"] = .string(hex)
            return try await update(id: id, values: ["personalisation": .object(personalisation)])
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Always scoped to a single row by primary key. Zero returned rows means the
    /// write did not land (row missing or RLS refused it), which is reported as a
    /// failure rather than silently ignored.
    private func update(id: UUID, values: [String: AnyJSON]) async throws -> Profile {
        do {
            let rows: [Profile] = try await client.from("profiles")
                .update(values)
                .eq("id", value: id)
                .select(Self.columns)
                .execute()
                .value
            guard let profile = rows.first else { throw DataServiceError.server }
            return profile
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}
