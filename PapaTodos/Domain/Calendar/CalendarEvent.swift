import Foundation

/// The calendar event for a chore, built the way PapaBoard's `src/lib/calendar.js` builds
/// its `.ics` file and Google Calendar link (specification.md section 9.9):
///
/// - date-only chore: a one-day all-day event, with alerts one day before and on the day;
/// - timed chore: a 30-minute event, with alerts two hours and 30 minutes before.
nonisolated struct CalendarEventDraft: Equatable, Sendable {
    static let timedEventDuration: TimeInterval = 30 * 60
    static let defaultAppName = "Papa Todos"

    var title: String
    var notes: String
    var isAllDay: Bool
    /// Timed: the due time. All-day: the start of the due day.
    var start: Date
    /// Timed: `start` + 30 minutes. All-day: the start of the *following* day (exclusive).
    var end: Date
    /// Alert times in seconds relative to `start` (negative = before).
    var alarmOffsets: [TimeInterval]

    /// Nil when the chore has no due date.
    static func make(
        for chore: Chore, appName: String = defaultAppName, calendar: Calendar = .current
    ) -> CalendarEventDraft? {
        guard let due = chore.dueDate else { return nil }
        let timed = DueDateRule.hasDueTime(due, calendar: calendar)
        let title = eventTitle(for: chore, appName: appName)
        let notes = eventDescription(for: chore, appName: appName)

        if timed {
            return CalendarEventDraft(
                title: title, notes: notes, isAllDay: false, start: due,
                end: due.addingTimeInterval(timedEventDuration),
                alarmOffsets: [-2 * 3600, -30 * 60]
            )
        }
        let dayStart = calendar.startOfDay(for: due)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return CalendarEventDraft(
            title: title, notes: notes, isAllDay: true, start: dayStart, end: nextDay,
            alarmOffsets: [-86_400, 0]
        )
    }

    static func eventTitle(for chore: Chore, appName: String = defaultAppName) -> String {
        let trimmed = chore.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(appName) chore" : "\(appName): \(trimmed)"
    }

    /// The description, the assignee, and (for the Google link) a note about the alerts.
    static func eventDescription(for chore: Chore, appName: String = defaultAppName, includeReminderNote: Bool = false) -> String {
        var lines: [String] = []
        let text = DescriptionHTML.calendarText(chore.description)
        if !text.isEmpty { lines.append(text) }
        if let name = chore.assignedProfile?.fullName, !name.isEmpty { lines.append("Assigned to: \(name)") }
        if includeReminderNote, let due = chore.dueDate {
            lines.append(reminderNote(timed: DueDateRule.hasDueTime(due)))
        }
        return lines.isEmpty ? "\(appName) chore" : lines.joined(separator: "\n\n")
    }

    static func reminderNote(timed: Bool) -> String {
        timed ? "Reminder: alerts 2 hours before and 30 minutes before." : "Reminder: alerts 1 day before and on the day."
    }
}

nonisolated extension DescriptionHTML {
    /// Ported from `htmlToText` in `calendar.js`: line breaks for `<br>` and closing block
    /// tags, tags removed, entities decoded, blank lines and repeated spaces collapsed.
    static func calendarText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        var text = value
        if looksLikeHTML(value) {
            let broken = value
                .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"</(p|div|li|h[1-6]|blockquote|tr)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            text = visibleText(sanitizedNodes(broken))
        }
        return text
            .replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func visibleText(_ nodes: [Node]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let text): text
            case .element(let element): visibleText(element.children)
            }
        }.joined()
    }
}
