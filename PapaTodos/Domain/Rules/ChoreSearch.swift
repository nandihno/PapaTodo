import Foundation

/// Search matching, ported from `choreMatchesSearch`/`getStatusLabel` in PapaBoard's
/// `HomeScreen.jsx`: a case-insensitive substring match across title, description,
/// assignee name, creator name, and the human-readable status.
///
/// Like PapaBoard's `descriptionToPlainText`, the description is reduced to its visible
/// text first, so markup such as `<ul>` never matches a search.
nonisolated enum ChoreSearch {
    static func statusLabel(for status: ChoreStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }

    static func matches(
        _ chore: Chore,
        query: String,
        assignedName: String?,
        createdName: String?
    ) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let searchableText = [
            chore.title,
            DescriptionHTML.plainText(chore.description),
            assignedName,
            createdName,
            statusLabel(for: chore.status),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        return searchableText.contains(normalizedQuery)
    }
}
