import Foundation

/// Search matching, ported from `choreMatchesSearch`/`getStatusLabel` in PapaBoard's
/// `HomeScreen.jsx`: a case-insensitive substring match across title, description,
/// assignee name, creator name, and the human-readable status.
///
/// PapaBoard runs `description` through `descriptionToPlainText` (HTML tag
/// stripping) before searching it. That sanitizer needs a real HTML parser and is
/// Phase 3 scope (rich-text rendering/editing) — until it exists, `description` is
/// searched as-is, which is correct for plain-text descriptions and only degrades
/// (searches raw markup) for HTML ones.
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
            chore.description,
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
