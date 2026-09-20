import Foundation

/// The Google Calendar "render" link, ported from `getGoogleCalendarUrl` in PapaBoard's
/// `calendar.js`: title, local start/end, description and the time zone.
nonisolated enum GoogleCalendarURL {
    static func make(
        for chore: Chore, appName: String = CalendarEventDraft.defaultAppName, calendar: Calendar = .current
    ) -> URL? {
        guard let due = chore.dueDate else { return nil }
        let timed = DueDateRule.hasDueTime(due, calendar: calendar)

        let dates: String
        if timed {
            let end = due.addingTimeInterval(CalendarEventDraft.timedEventDuration)
            dates = "\(stamp(due, timed: true, calendar: calendar))/\(stamp(end, timed: true, calendar: calendar))"
        } else {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: due) ?? due
            dates = "\(stamp(due, timed: false, calendar: calendar))/\(stamp(nextDay, timed: false, calendar: calendar))"
        }

        var parameters: [(String, String)] = [
            ("action", "TEMPLATE"),
            ("text", CalendarEventDraft.eventTitle(for: chore, appName: appName)),
            ("dates", dates),
            ("details", CalendarEventDraft.eventDescription(for: chore, appName: appName, includeReminderNote: true)),
        ]
        if !calendar.timeZone.identifier.isEmpty { parameters.append(("ctz", calendar.timeZone.identifier)) }

        let query = parameters.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
        return URL(string: "https://calendar.google.com/calendar/render?" + query)
    }

    /// `yyyyMMdd` or `yyyyMMdd'T'HHmmss` in the calendar's time zone (`formatCalendarDate(Time)`).
    static func stamp(_ date: Date, timed: Bool, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard timed else { return day }
        return day + String(format: "T%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// `application/x-www-form-urlencoded`, as JavaScript's `URLSearchParams` writes it:
    /// letters, digits and `*-._` stay, a space becomes `+`, everything else is percent-encoded.
    static func formEncode(_ value: String) -> String {
        var output = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "*"), UInt8(ascii: "-"),
                 UInt8(ascii: "."), UInt8(ascii: "_"):
                output.append(Character(UnicodeScalar(byte)))
            case UInt8(ascii: " "):
                output.append("+")
            default:
                output += String(format: "%%%02X", byte)
            }
        }
        return output
    }
}
