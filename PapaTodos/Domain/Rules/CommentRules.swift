import Foundation

/// "3m ago" style timestamps, ported from `formatTimeAgo` in PapaBoard's `ChoreDetailScreen.jsx`.
nonisolated enum CommentTime {
    static func label(for date: Date, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.abbreviated)
        ).replacingOccurrences(of: ",", with: "")
    }
}

/// A comment body is valid when it has visible text after trimming.
nonisolated enum CommentBody {
    static func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The ordered comment list for one chore. Applying the same change twice, or a change
/// for something already loaded, never produces a duplicate: a comment that arrives from
/// both the insert response and the Realtime stream appears once.
nonisolated struct CommentThread: Equatable, Sendable {
    private(set) var comments: [ChoreComment] = []

    init(_ comments: [ChoreComment] = []) {
        replace(with: comments)
    }

    /// Replaces the whole list (initial load, reload after reconnecting).
    mutating func replace(with fetched: [ChoreComment]) {
        var seen: [UUID: ChoreComment] = [:]
        for comment in fetched { seen[comment.id] = comment }
        comments = Self.sorted(Array(seen.values))
    }

    mutating func apply(_ change: CommentChange) {
        switch change {
        case .inserted(let comment), .updated(let comment):
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index] = comment
            } else {
                comments = Self.sorted(comments + [comment])
            }
        case .deleted(let id):
            comments.removeAll { $0.id == id }
        }
    }

    /// Oldest first, with the id as a stable tie-break.
    private static func sorted(_ comments: [ChoreComment]) -> [ChoreComment] {
        comments.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

extension ChoreStatus {
    /// The status cycle: pending, in progress, done, then back to pending.
    nonisolated var next: ChoreStatus {
        switch self {
        case .pending: .inProgress
        case .inProgress: .done
        case .done: .pending
        }
    }
}
