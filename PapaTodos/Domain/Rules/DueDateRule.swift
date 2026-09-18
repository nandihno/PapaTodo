import Foundation

/// Date-only vs. timed chore semantics, ported from PapaBoard's `src/lib/dueDates.js`
/// (see docs/papaboard-parity-checklist.md). A chore is "date-only" when its stored
/// `due_date` falls exactly on local noon — the legacy sentinel the web app writes
/// when no time was selected. Do not infer date-only status any other way: this
/// exact check must be used everywhere (parsing, display, editing, sorting,
/// calendar creation) or behavior will drift from the web client.
nonisolated enum DueDateRule {
    static let dateOnlySentinelHour = 12

    /// True if `date` carries a real time-of-day (i.e. is not the local-noon sentinel).
    static func hasDueTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return components.hour != dateOnlySentinelHour
            || components.minute != 0
            || components.second != 0
    }

    static func isDateOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        !hasDueTime(date, calendar: calendar)
    }

    /// Builds the local-noon sentinel timestamp for a date-only chore.
    static func dateOnlyTimestamp(year: Int, month: Int, day: Int, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = dateOnlySentinelHour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    /// Builds a timed chore's absolute timestamp from a local date and time.
    static func timedTimestamp(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar = .current
    ) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }
}

/// Semantic due state for a chore card, independent of its display string.
/// Ported from `getDueDisplay` in PapaBoard's `src/lib/dueDates.js`. The web
/// version also special-cases "tomorrow" and a same-vs-later-week split, but
/// those only ever affect the *label*, not the tone — every non-today,
/// non-overdue, non-done chore resolves to `.upcoming` there, so this is
/// behaviorally identical, just without the dead branches.
nonisolated enum DueTone: Sendable, Equatable {
    case done
    case overdue
    case today
    case upcoming
}

nonisolated enum ChoreDueState {
    static func tone(for chore: Chore, now: Date = Date(), calendar: Calendar = .current) -> DueTone {
        if chore.status == .done {
            return .done
        }
        guard let dueDate = chore.dueDate else {
            return .upcoming
        }

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)
        let dueHasTime = DueDateRule.hasDueTime(dueDate, calendar: calendar)

        if dueDay < today || (dueHasTime && dueDay == today && dueDate < now) {
            return .overdue
        }
        if dueDay == today {
            return .today
        }
        return .upcoming
    }

    /// Sort bucket, ported from `getDueSortRank`: 0 = due today, 1 = overdue,
    /// 2 = future, 3 = no due date.
    static func sortRank(for chore: Chore, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let dueDate = chore.dueDate else { return 3 }

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)

        if dueDay == today { return 0 }
        if dueDay < today { return 1 }
        return 2
    }

    /// Sort key within a rank, ported from `getDueSortTime`: overdue chores sort by
    /// *negative* due time so the most-recently-overdue (largest/closest-to-now
    /// timestamp) sorts first; every other rank sorts by raw due time ascending.
    static func sortKey(for chore: Chore, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        guard let dueDate = chore.dueDate else { return .greatestFiniteMagnitude }

        let dueTime = dueDate.timeIntervalSince1970
        return sortRank(for: chore, now: now, calendar: calendar) == 1 ? -dueTime : dueTime
    }
}
