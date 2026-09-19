import Foundation
import Supabase

nonisolated struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    func fetchProfile(id: UUID) async throws -> Profile? {
        do {
            let rows: [Profile] = try await client.from("profiles")
                .select("id, full_name, avatar_url, personalisation")
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
}
