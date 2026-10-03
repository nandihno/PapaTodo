import Foundation

/// Read-only offline copies of recently viewed chores (docs/phase-8-offline-plan.md).
///
/// Supabase stays the source of truth: entries are only ever written from a successful fetch.
/// Every entry belongs to one account. Failures are swallowed, because the cache must never
/// stop the live app from working, so none of these methods throw.
nonisolated protocol ChoreCache: Sendable {
    /// Saves or replaces the entry, marks it as just viewed, drops photos the chore no longer
    /// shows, and evicts the least recently viewed entries beyond the limit.
    func save(_ entry: CachedChore, userID: UUID) async
    func entry(choreID: UUID, userID: UUID) async -> CachedChore?
    /// All of the account's entries, most recently viewed first.
    func entries(userID: UUID) async -> [CachedChore]
    func markViewed(choreID: UUID, userID: UUID) async
    func remove(choreID: UUID, userID: UUID) async
    /// Erases everything, for every account (sign-out, session expiry).
    func removeAll() async

    /// Stores a photo of a saved chore. Ignored if the chore isn't saved or the photo is no
    /// longer one of its photos. May evict other chores to stay under the size cap.
    func savePhoto(_ data: Data, url: URL, choreID: UUID, userID: UUID) async
    func photo(url: URL, userID: UUID) async -> Data?
    func storedPhotoURLs(choreID: UUID, userID: UUID) async -> Set<URL>
}
