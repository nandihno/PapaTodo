import Foundation

/// The due-date text shown on a chore card, ported from the label half of
/// `getDueDisplay` in PapaBoard's `src/lib/dueDates.js` (the tone half lives in
/// `ChoreDueState`). Date and time follow the user's locale rather than the
/// web's hard-coded `en-AU`.
nonisolated enum ChoreDueLabel {
    static func label(
        for chore: Chore,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if chore.status == .done { return "Done" }
        guard let dueDate = chore.dueDate else { return "No due date" }

        let suffix = DueDateRule.hasDueTime(dueDate, calendar: calendar)
            ? " at \(timeText(dueDate, calendar: calendar, locale: locale))"
            : ""

        switch ChoreDueState.tone(for: chore, now: now, calendar: calendar) {
        case .overdue:
            return "Overdue\(suffix)"
        case .today:
            return "Today\(suffix)"
        case .done, .upcoming:
            let today = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            if calendar.startOfDay(for: dueDate) == tomorrow {
                return "Tomorrow\(suffix)"
            }
            return "\(dayText(dueDate, calendar: calendar, locale: locale))\(suffix)"
        }
    }

    private static func timeText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    /// Short weekday, day and month with commas removed, like the web's
    /// `toLocaleDateString(..., { weekday: 'short', day, month: 'short' }).replace(',', '')`.
    private static func dayText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
        )
        .replacingOccurrences(of: ",", with: "")
    }

    /// The long due date on the detail screen, ported from `formatDetailDueDate`:
    /// "Sunday 20 September 2026", with " at 3:00 pm" when a time was chosen.
    static func detail(
        for dueDate: Date?, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        guard let dueDate else { return "No due date" }
        let day = dueDate.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).day().month(.wide).year()
        ).replacingOccurrences(of: ",", with: "")
        guard DueDateRule.hasDueTime(dueDate, calendar: calendar) else { return day }
        return "\(day) at \(timeText(dueDate, calendar: calendar, locale: locale))"
    }
}
