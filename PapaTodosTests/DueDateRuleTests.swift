import Foundation
import Testing
@testable import PapaTodos

struct DueDateRuleTests {
    let calendar = Calendar.current

    @Test func exactLocalNoonIsDateOnly() {
        let noon = DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 10, calendar: calendar)!
        #expect(DueDateRule.isDateOnly(noon, calendar: calendar))
        #expect(!DueDateRule.hasDueTime(noon, calendar: calendar))
    }

    @Test func oneMinutePastNoonIsTimed() {
        let almostNoon = DueDateRule.timedTimestamp(
            year: 2026, month: 3, day: 10, hour: 12, minute: 1, calendar: calendar
        )!
        #expect(!DueDateRule.isDateOnly(almostNoon, calendar: calendar))
        #expect(DueDateRule.hasDueTime(almostNoon, calendar: calendar))
    }

    @Test func midnightIsTimedNotDateOnly() {
        // The sentinel is specifically local noon — midnight must not be confused for it.
        let midnight = DueDateRule.timedTimestamp(
            year: 2026, month: 3, day: 10, hour: 0, minute: 0, calendar: calendar
        )!
        #expect(DueDateRule.hasDueTime(midnight, calendar: calendar))
    }

    @Test func dateOnlyTimestampRoundTripsToTheSameCalendarDay() {
        let date = DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 10, calendar: calendar)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 10)
        #expect(components.hour == 12)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }
}
