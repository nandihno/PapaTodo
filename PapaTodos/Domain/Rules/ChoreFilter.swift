import Foundation

/// The three Home tabs, per specification.md section 9.2.
nonisolated enum HomeTab: String, Sendable, CaseIterable {
    case mine
    case all
    case done
}

/// Tab membership, ported from `choreBelongsInTab` in PapaBoard's `HomeScreen.jsx`.
nonisolated enum ChoreFilter {
    static func belongs(_ chore: Chore, in tab: HomeTab, currentUserID: UUID) -> Bool {
        if tab == .done {
            return chore.status == .done
        }
        if chore.status == .done {
            return false
        }
        if tab == .mine {
            return chore.assignedTo == currentUserID
        }
        return true
    }
}
