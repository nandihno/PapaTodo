import Foundation

/// A chore as last fetched from Supabase, kept on the phone so it can be read offline
/// (docs/phase-8-offline-plan.md). Holds everything the detail screen shows except photos,
/// which the cache stores separately.
nonisolated struct CachedChore: Codable, Sendable, Equatable {
    var chore: Chore
    var comments: [ChoreComment]
    /// Everyone the chore or its comments mention, so names and colours render offline.
    var people: [ProfileSummary]
    /// When this copy was fetched from Supabase.
    var savedAt: Date

    /// Every photo URL the chore currently shows: its attachments plus the legacy primary image.
    var photoURLs: Set<URL> {
        var urls = Set((chore.attachments ?? []).map(\.publicURL))
        if let imageURL = chore.imageURL { urls.insert(imageURL) }
        return urls
    }
}
