import Foundation

nonisolated protocol ProfileRepository: Sendable {
    func fetchProfile(id: UUID) async throws -> Profile?
    func fetchProfiles() async throws -> [ProfileSummary]
}
