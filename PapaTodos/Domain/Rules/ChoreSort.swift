import Foundation

/// Chore list ordering, ported from `compareChores` in PapaBoard's `HomeScreen.jsx`:
/// due today, then overdue (most recently overdue first), then future ascending,
/// then no due date, with newest creation as the final tie-breaker.
nonisolated enum ChoreSort {
    static func areInOrder(_ lhs: Chore, _ rhs: Chore, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let lhsRank = ChoreDueState.sortRank(for: lhs, now: now, calendar: calendar)
        let rhsRank = ChoreDueState.sortRank(for: rhs, now: now, calendar: calendar)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let lhsKey = ChoreDueState.sortKey(for: lhs, now: now, calendar: calendar)
        let rhsKey = ChoreDueState.sortKey(for: rhs, now: now, calendar: calendar)
        if lhsKey != rhsKey {
            return lhsKey < rhsKey
        }

        return lhs.createdAt > rhs.createdAt
    }

    static func sorted(_ chores: [Chore], now: Date = Date(), calendar: Calendar = .current) -> [Chore] {
        chores.sorted { areInOrder($0, $1, now: now, calendar: calendar) }
    }
}
