import Foundation
import Testing
@testable import PapaTodos

struct HomeListTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return calendar
    }()
    let locale = Locale(identifier: "en_AU")
    let me = UUID()
    let other = UUID()

    private func date(_ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }
    private var now: Date { date(10) }

    private func chore(
        _ title: String, assignedTo: UUID? = nil, status: ChoreStatus = .pending,
        due: Date? = nil, created: Date? = nil, description: String? = nil,
        assignee: String? = nil, creator: String? = nil
    ) -> Chore {
        Chore(
            id: UUID(), title: title, description: description, assignedTo: assignedTo, createdBy: nil,
            status: status, dueDate: due, imageURL: nil,
            createdAt: created ?? date(1), updatedAt: date(1),
            assignedProfile: assignee.map { ProfileSummary(id: assignedTo ?? UUID(), fullName: $0, avatarURL: nil) },
            createdProfile: creator.map { ProfileSummary(id: UUID(), fullName: $0, avatarURL: nil) }
        )
    }

    private func titles(_ tab: HomeTab, query: String = "", chores: [Chore], profile: Profile? = nil) -> [String] {
        HomeList.visibleChores(
            from: chores, tab: tab, query: query, currentUserID: me, currentProfile: profile,
            now: now, calendar: calendar
        ).map(\.title)
    }

    // MARK: tabs

    @Test func tabsPartitionActiveAndDoneChores() {
        let chores = [
            chore("mine active", assignedTo: me),
            chore("theirs active", assignedTo: other),
            chore("mine done", assignedTo: me, status: .done),
            chore("theirs done", assignedTo: other, status: .done),
            chore("unassigned"),
        ]
        #expect(Set(titles(.mine, chores: chores)) == ["mine active"])
        #expect(Set(titles(.all, chores: chores)) == ["mine active", "theirs active", "unassigned"])
        #expect(Set(titles(.done, chores: chores)) == ["mine done", "theirs done"])
    }

    // MARK: sort (spec 9.2)

    @Test func sortsTodayThenOverdueRecentFirstThenFutureThenNoDate() {
        let chores = [
            chore("no date"),
            chore("future far", due: date(20)),
            chore("overdue old", due: date(2)),
            chore("today", due: date(10, hour: 18)),
            chore("future near", due: date(12)),
            chore("overdue recent", due: date(9)),
        ]
        #expect(titles(.all, chores: chores) == [
            "today", "overdue recent", "overdue old", "future near", "future far", "no date",
        ])
    }

    @Test func newestCreatedBreaksTies() {
        let chores = [
            chore("older", created: date(1)),
            chore("newer", created: date(5)),
        ]
        #expect(titles(.all, chores: chores) == ["newer", "older"])
    }

    // MARK: search

    @Test func searchMatchesTitleDescriptionPeopleAndStatus() {
        let chores = [
            chore("Vacuum", description: "under the couch"),
            chore("Bins", assignee: "Mum", creator: "Dad"),
            chore("Laundry", status: .inProgress),
        ]
        #expect(titles(.all, query: "couch", chores: chores) == ["Vacuum"])
        #expect(titles(.all, query: "MUM", chores: chores) == ["Bins"])
        #expect(titles(.all, query: "dad", chores: chores) == ["Bins"])
        #expect(titles(.all, query: "in progress", chores: chores) == ["Laundry"])
        #expect(titles(.all, query: "  ", chores: chores).count == 3)
        #expect(titles(.all, query: "zzz", chores: chores).isEmpty)
    }

    @Test func searchAppliesWithinTheActiveTab() {
        let chores = [
            chore("Bins", assignedTo: me),
            chore("Bins outside", assignedTo: other),
        ]
        #expect(titles(.mine, query: "bins", chores: chores) == ["Bins"])
    }

    // MARK: current-user overlay

    @Test func freshProfileNameIsSearchableBeforeRefetch() {
        let chores = [chore("Bins", assignedTo: me, assignee: "Old Name")]
        #expect(titles(.all, query: "new name", chores: chores).isEmpty)

        let profile = Profile(id: me, fullName: "New Name", avatarURL: nil, personalisation: .init())
        #expect(titles(.all, query: "new name", chores: chores, profile: profile) == ["Bins"])
    }

    @Test func overlayLeavesOtherPeoplesChoresAlone() {
        let profile = Profile(id: me, fullName: "Me", avatarURL: nil, personalisation: .init())
        let theirs = chore("Theirs", assignedTo: other, assignee: "Them")
        #expect(theirs.mergingCurrentUser(profile).assignedProfile?.fullName == "Them")
    }

    // MARK: copy

    @Test func summaryAndEmptyCopyMatchTheWeb() {
        #expect(HomeList.summary(tab: .mine, query: "", resultCount: 0) == "Showing active chores assigned to you, due today first.")
        #expect(HomeList.summary(tab: .done, query: "", resultCount: 0) == "Showing completed family chores, due today first.")
        #expect(HomeList.summary(tab: .all, query: "", resultCount: 0) == "Showing active family chores, due today first.")
        #expect(HomeList.summary(tab: .all, query: " bins ", resultCount: 1) == "1 result for \"bins\".")
        #expect(HomeList.summary(tab: .all, query: "x", resultCount: 2) == "2 results for \"x\".")
        #expect(HomeList.emptyTitle(tab: .mine, query: "") == "No chores assigned to you.")
        #expect(HomeList.emptyTitle(tab: .done, query: "") == "No completed chores yet.")
        #expect(HomeList.emptyTitle(tab: .all, query: "") == "No chores yet.")
        #expect(HomeList.emptyTitle(tab: .all, query: "q") == "No chores match your search.")
        #expect(HomeList.emptyDetail(query: "") == "A quiet board for now.")
        #expect(HomeList.emptyDetail(query: "q") == "Try another title, note, person, or status.")
    }

    // MARK: due label

    @Test func dueLabels() {
        func label(_ due: Date?, status: ChoreStatus = .pending) -> String {
            ChoreDueLabel.label(
                for: chore("x", status: status, due: due), now: now, calendar: calendar, locale: locale
            )
        }
        let noon = { (day: Int) in date(day, hour: 12) }  // local-noon sentinel = date only

        #expect(label(nil) == "No due date")
        #expect(label(noon(10), status: .done) == "Done")
        #expect(label(noon(10)) == "Today")
        #expect(label(noon(11)) == "Tomorrow")
        #expect(label(noon(8)) == "Overdue")
        #expect(label(date(10, hour: 15, minute: 30)).hasPrefix("Today at 3:30"))
        #expect(label(date(10, hour: 8, minute: 15)).hasPrefix("Overdue at 8:15"))
        #expect(label(date(11, hour: 9, minute: 5)).hasPrefix("Tomorrow at 9:05"))

        let future = label(noon(20))
        #expect(!future.contains(","))
        #expect(future.contains("20"))
        #expect(future.contains("Mar"))
    }

    // MARK: attachments

    @Test func attachmentsSortAndFallBackToLegacyImage() throws {
        let base = chore("x")
        func attachment(order: Int, at day: Int, name: String) -> ChoreAttachment {
            ChoreAttachment(
                id: UUID(), choreId: base.id, storagePath: name, publicURL: URL(string: "https://e.com/\(name)")!,
                fileName: name, mimeType: nil, sortOrder: order, createdBy: nil, createdAt: date(day)
            )
        }
        var withRows = base
        withRows.attachments = [
            attachment(order: 1, at: 1, name: "b"), attachment(order: 0, at: 5, name: "a2"),
            attachment(order: 0, at: 2, name: "a1"),
        ]
        #expect(ChoreAttachments.all(for: withRows).map(\.storagePath) == ["a1", "a2", "b"])
        #expect(ChoreAttachments.primary(for: withRows)?.storagePath == "a1")

        var legacy = base
        legacy.imageURL = URL(string: "https://e.com/old.jpg")
        let legacyAll = ChoreAttachments.all(for: legacy)
        #expect(legacyAll.count == 1)
        #expect(legacyAll.first?.publicURL.lastPathComponent == "old.jpg")

        #expect(ChoreAttachments.all(for: base).isEmpty)
        #expect(ChoreAttachments.primary(for: base) == nil)

        // Rows win over the legacy field when both exist.
        var both = withRows
        both.imageURL = URL(string: "https://e.com/old.jpg")
        #expect(ChoreAttachments.all(for: both).count == 3)
    }
}
