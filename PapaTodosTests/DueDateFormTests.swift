import Foundation
import Testing
@testable import PapaTodos

struct DueDateFormTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func expect(_ date: Date, in calendar: Calendar, is expected: (Int, Int, Int, Int, Int), sourceLocation: SourceLocation = #_sourceLocation) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(
            [parts.year, parts.month, parts.day, parts.hour, parts.minute] == [expected.0, expected.1, expected.2, expected.3, expected.4],
            sourceLocation: sourceLocation
        )
    }

    private let zones = ["Australia/Melbourne", "America/Los_Angeles", "Europe/London", "Pacific/Auckland", "Asia/Kolkata"]

    @Test func noDueDateStoresNothingAndIgnoresAStaleTime() {
        let calendar = calendar("Australia/Melbourne")
        var fields = DueDateForm.fields(for: nil, calendar: calendar)
        #expect(!fields.hasDueDate)
        fields.hasDueTime = true   // a time can't exist without a date
        #expect(DueDateForm.timestamp(for: fields, calendar: calendar) == nil)
    }

    @Test func aDateOnlyChoreUsesLocalNoonAndRoundTripsExactly() throws {
        for zone in zones {
            let calendar = calendar(zone)
            // Every day of a year, so DST changes in each zone are crossed.
            for offset in stride(from: 0, to: 365, by: 3) {
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)!
                let components = calendar.dateComponents([.year, .month, .day], from: day)
                let stored = try #require(DueDateRule.dateOnlyTimestamp(year: components.year!, month: components.month!, day: components.day!, calendar: calendar))

                let fields = DueDateForm.fields(for: stored, calendar: calendar)
                #expect(fields.hasDueDate && !fields.hasDueTime, "\(zone) \(components)")
                #expect(DueDateForm.timestamp(for: fields, calendar: calendar) == stored, "\(zone) \(components)")
                #expect(calendar.component(.hour, from: stored) == 12)
            }
        }
    }

    @Test func aTimedChoreRoundTripsToTheMinute() throws {
        let calendar = calendar("Australia/Melbourne")
        for (hour, minute) in [(0, 0), (0, 1), (9, 30), (11, 59), (12, 1), (13, 0), (23, 59)] {
            let stored = try #require(DueDateRule.timedTimestamp(year: 2026, month: 6, day: 15, hour: hour, minute: minute, calendar: calendar))
            let fields = DueDateForm.fields(for: stored, calendar: calendar)
            #expect(fields.hasDueTime, "\(hour):\(minute)")
            #expect(DueDateForm.timestamp(for: fields, calendar: calendar) == stored, "\(hour):\(minute)")
        }
    }

    @Test func aTimedChoreAtExactlyNoonIsIndistinguishableFromDateOnly() throws {
        // The legacy sentinel: the web app cannot tell them apart either, so neither can we.
        let calendar = calendar("Australia/Melbourne")
        let noon = try #require(DueDateRule.timedTimestamp(year: 2026, month: 6, day: 15, hour: 12, minute: 0, calendar: calendar))
        #expect(!DueDateForm.fields(for: noon, calendar: calendar).hasDueTime)
    }

    @Test func turningOffTheTimeKeepsTheDayAsDateOnly() throws {
        let calendar = calendar("Australia/Melbourne")
        let stored = try #require(DueDateRule.timedTimestamp(year: 2026, month: 6, day: 15, hour: 9, minute: 30, calendar: calendar))
        var fields = DueDateForm.fields(for: stored, calendar: calendar)
        fields.hasDueTime = false
        let result = try #require(DueDateForm.timestamp(for: fields, calendar: calendar))
        expect(result, in: calendar, is: (2026, 6, 15, 12, 0))
    }

    @Test func aFormattedInstantWithSecondsOrFractionsDoesNotBreakTheDay() throws {
        // Stored values can carry seconds/fractions; the form works to the minute but the day must not move.
        let calendar = calendar("Australia/Melbourne")
        let stored = try #require(DueDateRule.timedTimestamp(year: 2026, month: 3, day: 1, hour: 23, minute: 59, calendar: calendar)).addingTimeInterval(30.75)
        let fields = DueDateForm.fields(for: stored, calendar: calendar)
        let result = try #require(DueDateForm.timestamp(for: fields, calendar: calendar))
        expect(result, in: calendar, is: (2026, 3, 1, 23, 59))
    }
}
