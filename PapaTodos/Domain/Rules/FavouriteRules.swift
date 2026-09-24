import Foundation

/// Pure rules behind favourite chores: title matching, suggestions, and reordering.
nonisolated enum FavouriteRules {
    /// The comparison key the database's unique index uses: trimmed and case-insensitive.
    /// Diacritics are also folded here so "Café" and "Cafe" suggest each other.
    static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether two titles would collide in the database (trimmed, case-insensitive).
    static func sameTitle(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Favourites whose title contains what's been typed, in the shared order, leaving out
    /// an exact match (it's already what the user has). Empty input suggests nothing.
    static func suggestions(for query: String, in templates: [ChoreTemplate], limit: Int = 3) -> [ChoreTemplate] {
        let needle = key(query)
        guard !needle.isEmpty else { return [] }
        return Array(
            templates
                .filter { key($0.title).contains(needle) && key($0.title) != needle }
                .prefix(limit)
        )
    }

    /// The position a new favourite gets: after everything already in the list.
    static func nextSortOrder(after templates: [ChoreTemplate]) -> Int {
        (templates.map(\.sortOrder).max() ?? -1) + 1
    }

    /// A list drag, with the same meaning as SwiftUI's `onMove` offsets (kept here so the store
    /// doesn't depend on SwiftUI).
    static func moving<Element>(_ items: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let moved = source.filter { items.indices.contains($0) }.map { items[$0] }
        var remaining = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(max(destination - source.count(in: 0..<destination), 0), remaining.count)
        remaining.insert(contentsOf: moved, at: insertAt)
        return remaining
    }

    /// The favourites in their new order, each with `sortOrder` equal to its index, and the
    /// positions that actually changed (the only rows worth writing).
    static func reordered(_ templates: [ChoreTemplate]) -> (list: [ChoreTemplate], changes: [UUID: Int]) {
        var changes: [UUID: Int] = [:]
        let list = templates.enumerated().map { index, template in
            var updated = template
            if template.sortOrder != index {
                updated.sortOrder = index
                changes[template.id] = index
            }
            return updated
        }
        return (list, changes)
    }
}
