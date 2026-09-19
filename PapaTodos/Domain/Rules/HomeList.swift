import Foundation

/// Composes the Home list the way PapaBoard's `HomeScreen.jsx` does: overlay the
/// current user's freshest profile, filter by tab, filter by search, then sort.
nonisolated enum HomeList {
    static func visibleChores(
        from chores: [Chore],
        tab: HomeTab,
        query: String,
        currentUserID: UUID,
        currentProfile: Profile?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Chore] {
        let merged = currentProfile.map { profile in chores.map { $0.mergingCurrentUser(profile) } } ?? chores
        return ChoreSort.sorted(
            merged.filter { chore in
                ChoreFilter.belongs(chore, in: tab, currentUserID: currentUserID)
                    && ChoreSearch.matches(
                        chore, query: query,
                        assignedName: chore.assignedProfile?.fullName,
                        createdName: chore.createdProfile?.fullName
                    )
            },
            now: now, calendar: calendar
        )
    }

    /// The one-line caption above the list (`getListSummary` plus the search summary).
    static func summary(tab: HomeTab, query: String, resultCount: Int) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "\(resultCount) \(resultCount == 1 ? "result" : "results") for \"\(trimmed)\"."
        }
        switch tab {
        case .mine: return "Showing active chores assigned to you, due today first."
        case .done: return "Showing completed family chores, due today first."
        case .all: return "Showing active family chores, due today first."
        }
    }

    static func emptyTitle(tab: HomeTab, query: String) -> String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No chores match your search."
        }
        switch tab {
        case .mine: return "No chores assigned to you."
        case .done: return "No completed chores yet."
        case .all: return "No chores yet."
        }
    }

    static func emptyDetail(query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "A quiet board for now."
            : "Try another title, note, person, or status."
    }
}

extension Chore {
    /// `mergeCurrentUserProfile`: lets a just-edited name/avatar show (and be
    /// searched) before the next full refetch by overlaying the current user's
    /// profile on the embedded assignee/creator snapshots.
    nonisolated func mergingCurrentUser(_ profile: Profile) -> Chore {
        var copy = self
        let summary = ProfileSummary(id: profile.id, fullName: profile.fullName, avatarURL: profile.avatarURL)
        if assignedTo == profile.id { copy.assignedProfile = summary }
        if createdBy == profile.id { copy.createdProfile = summary }
        return copy
    }
}
