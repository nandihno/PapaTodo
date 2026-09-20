import Foundation
import Testing
@testable import PapaTodos

struct CalendarEventTests {
    /// All expected values were produced by running PapaBoard's own `calendar.js` under
    /// `TZ=Australia/Melbourne` (with HTML entities decoded, as a browser does).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)!
    }

    private func chore(title: String, description: String?, due: String?, assignee: String?) -> Chore {
        Chore(
            id: UUID(), title: title, description: description, assignedTo: nil, createdBy: nil, status: .pending,
            dueDate: due.map(date), imageURL: nil, createdAt: Date(), updatedAt: Date(),
            assignedProfile: assignee.map { ProfileSummary(id: UUID(), fullName: $0, avatarURL: nil) }
        )
    }

    private var dateOnly: Chore {
        chore(title: "Take out bins", description: "<p>Bins &amp; lids</p><p>Second line</p>", due: "2026-09-24T02:00:00.000Z", assignee: "Mum")
    }
    private var timed: Chore {
        chore(title: "Fix & tidy: shed?", description: "Plain note, with; punctuation", due: "2026-09-24T05:30:00.000Z", assignee: "Dad")
    }
    private var bare: Chore {
        chore(title: "  ", description: "", due: "2026-12-31T13:00:00.000Z", assignee: nil)
    }

    // MARK: Google Calendar link (matches the web)

    @Test func googleLinkForADateOnlyChoreMatchesTheWeb() {
        let url = GoogleCalendarURL.make(for: dateOnly, appName: "PapaBoard", calendar: calendar)?.absoluteString
        #expect(url == "https://calendar.google.com/calendar/render?action=TEMPLATE&text=PapaBoard%3A+Take+out+bins&dates=20260924%2F20260925&details=Bins+%26+lids%0ASecond+line%0A%0AAssigned+to%3A+Mum%0A%0AReminder%3A+alerts+1+day+before+and+on+the+day.&ctz=Australia%2FMelbourne")
    }

    @Test func googleLinkForATimedChoreMatchesTheWeb() {
        let url = GoogleCalendarURL.make(for: timed, appName: "PapaBoard", calendar: calendar)?.absoluteString
        #expect(url == "https://calendar.google.com/calendar/render?action=TEMPLATE&text=PapaBoard%3A+Fix+%26+tidy%3A+shed%3F&dates=20260924T153000%2F20260924T160000&details=Plain+note%2C+with%3B+punctuation%0A%0AAssigned+to%3A+Dad%0A%0AReminder%3A+alerts+2+hours+before+and+30+minutes+before.&ctz=Australia%2FMelbourne")
    }

    @Test func googleLinkForAChoreWithNoTitleOrNotesMatchesTheWeb() {
        // 2026-12-31T13:00Z is midnight in Melbourne, so it is a timed chore (not the noon sentinel).
        let url = GoogleCalendarURL.make(for: bare, appName: "PapaBoard", calendar: calendar)?.absoluteString
        #expect(url == "https://calendar.google.com/calendar/render?action=TEMPLATE&text=PapaBoard+chore&dates=20270101T000000%2F20270101T003000&details=Reminder%3A+alerts+2+hours+before+and+30+minutes+before.&ctz=Australia%2FMelbourne")
    }

    @Test func noDueDateMeansNoLinkAndNoEvent() {
        let undated = chore(title: "x", description: nil, due: nil, assignee: nil)
        #expect(GoogleCalendarURL.make(for: undated, calendar: calendar) == nil)
        #expect(CalendarEventDraft.make(for: undated, calendar: calendar) == nil)
    }

    @Test func formEncodingMatchesURLSearchParams() {
        #expect(GoogleCalendarURL.formEncode("a b&c=d/é*-._~!'()") == "a+b%26c%3Dd%2F%C3%A9*-._%7E%21%27%28%29")
        #expect(GoogleCalendarURL.formEncode("line\nbreak") == "line%0Abreak")
    }

    // MARK: Apple Calendar event (spec 9.9)

    @Test func aDateOnlyChoreIsAOneDayAllDayEventWithDayBeforeAndDayOfAlerts() throws {
        let event = try #require(CalendarEventDraft.make(for: dateOnly, appName: "PapaBoard", calendar: calendar))
        #expect(event.isAllDay)
        #expect(event.start == calendar.startOfDay(for: date("2026-09-24T02:00:00.000Z")))
        #expect(event.end == calendar.date(byAdding: .day, value: 1, to: event.start))
        #expect(calendar.dateComponents([.day], from: event.start, to: event.end).day == 1)
        #expect(event.alarmOffsets == [-86_400, 0])
        #expect(event.title == "PapaBoard: Take out bins")
    }

    @Test func aTimedChoreIsA30MinuteEventWithTwoHourAndThirtyMinuteAlerts() throws {
        let event = try #require(CalendarEventDraft.make(for: timed, appName: "PapaBoard", calendar: calendar))
        #expect(!event.isAllDay)
        #expect(event.start == date("2026-09-24T05:30:00.000Z"))
        #expect(event.end.timeIntervalSince(event.start) == 30 * 60)
        #expect(event.alarmOffsets == [-7_200, -1_800])
    }

    @Test func theEventNotesHoldTheDescriptionAndTheAssignee() throws {
        let event = try #require(CalendarEventDraft.make(for: dateOnly, appName: "PapaBoard", calendar: calendar))
        #expect(event.notes == "Bins & lids\nSecond line\n\nAssigned to: Mum")
        let plain = try #require(CalendarEventDraft.make(for: timed, appName: "PapaBoard", calendar: calendar))
        #expect(plain.notes == "Plain note, with; punctuation\n\nAssigned to: Dad")
    }

    @Test func aChoreWithNothingToSayGetsAFallbackDescription() throws {
        let event = try #require(CalendarEventDraft.make(for: bare, appName: "PapaBoard", calendar: calendar))
        #expect(event.notes == "PapaBoard chore")
        #expect(event.title == "PapaBoard chore")
    }

    @Test func theDefaultAppNameIsTheProductName() throws {
        let event = try #require(CalendarEventDraft.make(for: dateOnly, calendar: calendar))
        #expect(event.title == "Papa Todos: Take out bins")
    }

    @Test func calendarTextDecodesEntitiesAndTidiesWhitespace() {
        #expect(DescriptionHTML.calendarText("<ul><li>a</li><li>b &lt;c&gt;</li></ul>") == "a\nb <c>")
        #expect(DescriptionHTML.calendarText("<p>one</p>\n\n<p>  two   words </p>") == "one\ntwo words")
        #expect(DescriptionHTML.calendarText("x<script>alert(1)</script>y<br>z") == "xy\nz")
        #expect(DescriptionHTML.calendarText("line1\n\n\nline2") == "line1\nline2")
        #expect(DescriptionHTML.calendarText(nil) == "")
    }
}

struct CommentRulesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_AU")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func ago(_ seconds: TimeInterval) -> String {
        CommentTime.label(for: now.addingTimeInterval(-seconds), now: now, locale: locale, calendar: calendar)
    }

    @Test func timeAgoMatchesTheWebThresholds() {
        #expect(ago(0) == "Just now")
        #expect(ago(59) == "Just now")
        #expect(ago(60) == "1m ago")
        #expect(ago(59 * 60 + 59) == "59m ago")
        #expect(ago(3600) == "1h ago")
        #expect(ago(23 * 3600 + 3599) == "23h ago")
        #expect(ago(86_400) == "1d ago")
        #expect(ago(6 * 86_400 + 3600) == "6d ago")
        #expect(ago(-300) == "Just now")   // a clock a little ahead of the server
    }

    @Test func olderCommentsShowADayAndMonth() {
        let label = ago(30 * 86_400)
        #expect(!label.contains(","))
        #expect(!label.contains("ago"))
        #expect(label.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    @Test func commentBodiesAreTrimmedAndMustHaveText() {
        #expect(CommentBody.validated("  hello  ") == "hello")
        #expect(CommentBody.validated("a\nb") == "a\nb")
        #expect(CommentBody.validated("   \n\t ") == nil)
        #expect(CommentBody.validated("") == nil)
    }

    // MARK: thread reconciliation

    private func comment(_ id: UUID = UUID(), body: String = "hi", at seconds: TimeInterval) -> ChoreComment {
        ChoreComment(id: id, choreId: UUID(), authorId: nil, body: body, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func aThreadIsOrderedOldestFirst() {
        let thread = CommentThread([comment(body: "second", at: 20), comment(body: "first", at: 10), comment(body: "third", at: 30)])
        #expect(thread.comments.map(\.body) == ["first", "second", "third"])
    }

    @Test func theSameCommentFromTwoSourcesAppearsOnce() {
        let shared = comment(body: "same", at: 10)
        var thread = CommentThread([])
        thread.apply(.inserted(shared))       // the insert response
        thread.apply(.inserted(shared))       // the Realtime echo of the same insert
        thread.apply(.inserted(shared))       // and a replay after reconnecting
        #expect(thread.comments.count == 1)
    }

    @Test func aFreshLoadNeverDuplicatesWhatArrivedFirst() {
        let early = comment(body: "early", at: 10)
        var thread = CommentThread([])
        thread.apply(.inserted(early))
        thread.replace(with: [early, comment(body: "later", at: 20)])
        #expect(thread.comments.map(\.body) == ["early", "later"])
        thread.replace(with: [early, early, comment(body: "later", at: 20)])
        #expect(thread.comments.count == 2)
    }

    @Test func updatesReplaceInPlaceAndUnknownUpdatesAreKept() {
        let id = UUID()
        var thread = CommentThread([comment(id, body: "old", at: 10)])
        thread.apply(.updated(comment(id, body: "edited", at: 10)))
        #expect(thread.comments.map(\.body) == ["edited"])
        thread.apply(.updated(comment(body: "arrived as an update", at: 20)))
        #expect(thread.comments.count == 2)
    }

    @Test func deletesRemoveOnlyThatCommentAndTolerateUnknownIDs() {
        let id = UUID()
        var thread = CommentThread([comment(id, at: 10), comment(body: "keep", at: 20)])
        thread.apply(.deleted(id: id))
        thread.apply(.deleted(id: id))
        thread.apply(.deleted(id: UUID()))
        #expect(thread.comments.map(\.body) == ["keep"])
    }

    @Test func aBurstOfChangesEndsInTheSameStateInAnyArrivalOrder() {
        let a = comment(body: "a", at: 10), b = comment(body: "b", at: 20), c = comment(body: "c", at: 30)
        var forward = CommentThread([]), backward = CommentThread([])
        [a, b, c].forEach { forward.apply(.inserted($0)) }
        [c, b, a].forEach { backward.apply(.inserted($0)) }
        #expect(forward == backward)
    }

    // MARK: status cycle

    @Test func theStatusCycleMatchesTheWeb() {
        #expect(ChoreStatus.pending.next == .inProgress)
        #expect(ChoreStatus.inProgress.next == .done)
        #expect(ChoreStatus.done.next == .pending)
    }
}
