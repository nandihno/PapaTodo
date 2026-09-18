import Foundation
import Testing
@testable import PapaTodos

struct ChoreSortTests {
    let calendar = Calendar.current
    let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 3, day: 10, hour: 9, minute: 0
    ))!

    private func chore(
        title: String,
        dueDate: Date?,
        createdAt: Date
    ) -> Chore {
        Chore(
            id: UUID(), title: title, description: nil,
            assignedTo: nil, createdBy: nil, status: .pending, dueDate: dueDate,
            imageURL: nil, createdAt: createdAt, updatedAt: createdAt
        )
    }

    @Test func ordersDueTodayThenOverdueThenFutureThenNoDueDate() {
        let dueToday = chore(
            title: "due today",
            dueDate: DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 10, calendar: calendar),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let overdueRecent = chore(
            title: "overdue recent",
            dueDate: DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 9, calendar: calendar),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let overdueOld = chore(
            title: "overdue old",
            dueDate: DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 3, calendar: calendar),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let future = chore(
            title: "future",
            dueDate: DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 15, calendar: calendar),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let noDueDate = chore(title: "no due date", dueDate: nil, createdAt: Date(timeIntervalSince1970: 0))

        // Deliberately shuffled input order.
        let input = [noDueDate, future, overdueOld, dueToday, overdueRecent]
        let sorted = input.sorted { ChoreSort.areInOrder($0, $1, now: now, calendar: calendar) }

        #expect(sorted.map(\.title) == ["due today", "overdue recent", "overdue old", "future", "no due date"])
    }

    @Test func tiesBreakByNewestCreationFirst() {
        let sameDueDate = DueDateRule.dateOnlyTimestamp(year: 2026, month: 3, day: 15, calendar: calendar)
        let older = chore(title: "older", dueDate: sameDueDate, createdAt: Date(timeIntervalSince1970: 0))
        let newer = chore(title: "newer", dueDate: sameDueDate, createdAt: Date(timeIntervalSince1970: 1000))

        let sorted = [older, newer].sorted { ChoreSort.areInOrder($0, $1, now: now, calendar: calendar) }

        #expect(sorted.map(\.title) == ["newer", "older"])
    }
}
