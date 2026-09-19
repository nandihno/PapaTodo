import Foundation

/// Converts between a chore's stored `due_date` and the form's separate date and optional
/// time controls, using the legacy local-noon sentinel for date-only chores
/// (`toDueTimestamp`, `toDateInputValue`, `toTimeInputValue` in PapaBoard's `dueDates.js`).
nonisolated enum DueDateForm {
    struct Fields: Equatable {
        var hasDueDate: Bool
        /// Any instant on the chosen day; only the calendar day is used.
        var day: Date
        var hasDueTime: Bool
        /// Any instant with the chosen hour and minute; only the time of day is used.
        var time: Date
    }

    /// Form fields for a stored due date (nil = no due date).
    static func fields(for dueDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Fields {
        guard let dueDate else {
            return Fields(hasDueDate: false, day: now, hasDueTime: false, time: noon(on: now, calendar: calendar))
        }
        let timed = DueDateRule.hasDueTime(dueDate, calendar: calendar)
        return Fields(hasDueDate: true, day: dueDate, hasDueTime: timed, time: timed ? dueDate : noon(on: dueDate, calendar: calendar))
    }

    /// The timestamp to store, or nil when there is no due date. A day with no time becomes
    /// local noon; a day with a time keeps the chosen hour and minute.
    static func timestamp(for fields: Fields, calendar: Calendar = .current) -> Date? {
        guard fields.hasDueDate else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: fields.day)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        if fields.hasDueTime {
            let time = calendar.dateComponents([.hour, .minute], from: fields.time)
            return DueDateRule.timedTimestamp(
                year: year, month: month, day: dayOfMonth, hour: time.hour ?? 0, minute: time.minute ?? 0, calendar: calendar
            )
        }
        return DueDateRule.dateOnlyTimestamp(year: year, month: month, day: dayOfMonth, calendar: calendar)
    }

    private static func noon(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: DueDateRule.dateOnlySentinelHour, minute: 0, second: 0, of: date) ?? date
    }
}
