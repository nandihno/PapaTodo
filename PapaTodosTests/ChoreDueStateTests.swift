import Foundation
import Testing
@testable import PapaTodos

struct ChoreDueStateTests {
    let calendar = Calendar.current
    // Fixed reference instant so tests never depend on the real current date.
    let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 3, day: 10, hour: 9, minute: 0
    ))!

    private func chore(
        status: ChoreStatus = .pending,
        dueDate: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Chore {
        Chore(
            id: UUID(), title: "Test chore", description: nil,
            assignedTo: nil, createdBy: nil, status: status, dueDate: dueDate,
            imageURL: nil, createdAt: createdAt, updatedAt: createdAt
        )
    }

    @Test func doneChoreIsAlwaysDoneRegardlessOfDueDate() {
        let overdueButDone = chore(
            status: .done,
            dueDate: DueDateRule.timedTimestamp(year: 2026, month: 3, day: 1, hour: 9, minute: 0, calendar: calendar)
        )
        #expect(ChoreDueState.tone(for: overdueButDone, now: now, calendar: calendar) == .done)
    }

    @Test func noDueDateIsUpcoming() {
        let chore = chore(dueDate: nil)
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .upcoming)
        #expect(ChoreDueState.sortRank(for: chore, now: now, calendar: calendar) == 3)
    }

    @Test func pastCalendarDayIsOverdue() {
        let chore = chore(dueDate: DueDateRule.dateOnlyTimestamp(
            year: 2026, month: 3, day: 8, calendar: calendar
        ))
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .overdue)
        #expect(ChoreDueState.sortRank(for: chore, now: now, calendar: calendar) == 1)
    }

    @Test func dateOnlyDueTodayIsTodayEvenBeforeNoon() {
        // now is 9am; a date-only (noon-sentinel) chore due today must never read as
        // overdue just because the sentinel time (noon) hasn't arrived yet.
        let chore = chore(dueDate: DueDateRule.dateOnlyTimestamp(
            year: 2026, month: 3, day: 10, calendar: calendar
        ))
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .today)
        #expect(ChoreDueState.sortRank(for: chore, now: now, calendar: calendar) == 0)
    }

    @Test func timedDueTodayBeforeNowIsOverdue() {
        let chore = chore(dueDate: DueDateRule.timedTimestamp(
            year: 2026, month: 3, day: 10, hour: 8, minute: 0, calendar: calendar
        ))
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .overdue)
        // Same calendar day, so it still ranks as "due today" for sorting purposes.
        #expect(ChoreDueState.sortRank(for: chore, now: now, calendar: calendar) == 0)
    }

    @Test func timedDueTodayAfterNowIsToday() {
        let chore = chore(dueDate: DueDateRule.timedTimestamp(
            year: 2026, month: 3, day: 10, hour: 15, minute: 0, calendar: calendar
        ))
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .today)
    }

    @Test func futureDateIsUpcoming() {
        let chore = chore(dueDate: DueDateRule.dateOnlyTimestamp(
            year: 2026, month: 3, day: 12, calendar: calendar
        ))
        #expect(ChoreDueState.tone(for: chore, now: now, calendar: calendar) == .upcoming)
        #expect(ChoreDueState.sortRank(for: chore, now: now, calendar: calendar) == 2)
    }

    @Test func moreRecentlyOverdueSortsBeforeOlderOverdue() {
        let yesterday = chore(dueDate: DueDateRule.dateOnlyTimestamp(
            year: 2026, month: 3, day: 9, calendar: calendar
        ))
        let lastWeek = chore(dueDate: DueDateRule.dateOnlyTimestamp(
            year: 2026, month: 3, day: 3, calendar: calendar
        ))
        let yesterdayKey = ChoreDueState.sortKey(for: yesterday, now: now, calendar: calendar)
        let lastWeekKey = ChoreDueState.sortKey(for: lastWeek, now: now, calendar: calendar)
        #expect(yesterdayKey < lastWeekKey)
    }
}
