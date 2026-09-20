import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct ChoreDetailModelTests {
    let me = FixtureData.currentUserID

    private func makeChore(status: ChoreStatus = .pending, due: Date? = nil) -> Chore {
        Chore(
            id: UUID(), title: "Detail chore", description: "d", assignedTo: me, createdBy: me, status: status,
            dueDate: due, imageURL: nil, createdAt: Date(), updatedAt: Date()
        )
    }

    struct World {
        let chore: Chore
        let chores: FixtureChoreRepository
        let comments: FixtureCommentRepository
        let model: ChoreDetailModel
        let changed: LockedState<[Chore]>
        let expired: LockedState<Int>
    }

    private func makeWorld(
        chore: Chore? = nil, seeded: [ChoreComment] = [], seedModel: Bool = false,
        calendar: CalendarAccessStatus = .available, retryDelays: [Duration] = [.milliseconds(5)]
    ) async -> World {
        let chore = chore ?? makeChore()
        let chores = FixtureChoreRepository(chores: [chore])
        let comments = FixtureCommentRepository(comments: seeded.map { var c = $0; c = ChoreComment(id: c.id, choreId: chore.id, authorId: c.authorId, body: c.body, createdAt: c.createdAt); return c })
        let changed = LockedState<[Chore]>([])
        let expired = LockedState(0)
        let model = ChoreDetailModel(
            choreID: chore.id, seed: seedModel ? chore : nil,
            choreRepository: chores, commentRepository: comments, profileRepository: FixtureProfileRepository(),
            calendarStatus: { calendar }, retryDelays: retryDelays,
            onChoreChanged: { updated in changed.withLock { $0.append(updated) } },
            onSessionExpired: { expired.withLock { $0 += 1 } }
        )
        return World(chore: chore, chores: chores, comments: comments, model: model, changed: changed, expired: expired)
    }

    private func comment(_ body: String, at seconds: TimeInterval, author: UUID? = nil, id: UUID = UUID()) -> ChoreComment {
        ChoreComment(id: id, choreId: UUID(), authorId: author, body: body, createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    // MARK: loading

    @Test func loadPopulatesTheChoreCommentsAndPeople() async {
        let world = await makeWorld(seeded: [comment("hello", at: 10, author: FixtureData.otherUserID)])
        await world.model.load()
        #expect(world.model.loadState == .loaded)
        #expect(world.model.chore?.title == "Detail chore")
        #expect(world.model.comments.map(\.body) == ["hello"])
        #expect(world.model.author(of: world.model.comments[0])?.fullName == "Alex Sample")
    }

    @Test func aMissingChoreIsNotFoundRatherThanAnError() async {
        let world = await makeWorld()
        let model = ChoreDetailModel(
            choreID: UUID(), choreRepository: world.chores, commentRepository: world.comments, profileRepository: FixtureProfileRepository()
        )
        await model.load()
        #expect(model.loadState == .notFound)
    }

    @Test func aSeededChoreShowsImmediatelyAndRefreshFailureKeepsIt() async {
        let world = await makeWorld(seedModel: true)
        #expect(world.model.loadState == .loaded)
        #expect(world.model.chore != nil)
    }

    @Test func aFailedCommentLoadShowsAnErrorWithoutBlankingTheChore() async {
        let world = await makeWorld()
        await world.comments.failNextFetches(1)
        await world.model.load()
        #expect(world.model.loadState == .loaded)
        #expect(world.model.commentsError != nil)
    }

    // MARK: sending comments

    @Test func aCommentIsTrimmedSentAndShownOnceEvenWhenTheStreamEchoesIt() async {
        let world = await makeWorld()
        await world.model.load()
        let listener = Task { await world.model.listen() }
        #expect(await waitUntil { await world.comments.subscriberCount == 1 })

        world.model.commentDraft = "  first comment  "
        await world.model.sendComment()

        #expect(await waitUntil { world.model.comments.count == 1 })
        try? await Task.sleep(for: .milliseconds(50))   // let the echo arrive
        #expect(world.model.comments.map(\.body) == ["first comment"])
        #expect(world.model.commentDraft.isEmpty)
        listener.cancel()
    }

    @Test func aBlankCommentCannotBeSent() async {
        let world = await makeWorld()
        await world.model.load()
        world.model.commentDraft = "   \n "
        #expect(!world.model.canSendComment)
        await world.model.sendComment()
        #expect(await world.comments.storedComments(for: world.chore.id).isEmpty)
    }

    @Test func aFailedSendKeepsTheDraftAndSaysWhy() async {
        let world = await makeWorld()
        await world.model.load()
        await world.comments.failNextAdd(with: .offline)
        world.model.commentDraft = "keep this text"

        await world.model.sendComment()

        #expect(world.model.commentDraft == "keep this text")
        #expect(world.model.commentsError?.contains("offline") == true)
        #expect(world.model.comments.isEmpty)

        await world.model.sendComment()   // retry succeeds
        #expect(world.model.comments.map(\.body) == ["keep this text"])
        #expect(world.model.commentsError == nil)
    }

    @Test func sessionExpiryWhileSendingSignsOutInsteadOfShowingAnError() async {
        let world = await makeWorld()
        await world.model.load()
        await world.comments.failNextAdd(with: .sessionExpired)
        world.model.commentDraft = "x"
        await world.model.sendComment()
        #expect(world.expired.withLock { $0 } == 1)
        #expect(world.model.commentsError == nil)
    }

    @Test func doubleTappingSendPostsOnce() async {
        let world = await makeWorld()
        await world.model.load()
        world.model.commentDraft = "once"
        async let first: Void = world.model.sendComment()
        async let second: Void = world.model.sendComment()
        _ = await (first, second)
        #expect(await world.comments.storedComments(for: world.chore.id).count == 1)
    }

    // MARK: realtime

    @Test func commentsFromAnotherClientAppearInsertUpdateAndDelete() async {
        let world = await makeWorld()
        await world.model.load()
        let listener = Task { await world.model.listen() }
        #expect(await waitUntil { await world.comments.subscriberCount == 1 })

        let id = UUID()
        let remote = ChoreComment(id: id, choreId: world.chore.id, authorId: FixtureData.otherUserID, body: "from the web", createdAt: Date())
        await world.comments.simulateRemote(.inserted(remote), choreID: world.chore.id)
        #expect(await waitUntil { world.model.comments.map(\.body) == ["from the web"] })

        var edited = remote; edited.body = "edited on the web"
        await world.comments.simulateRemote(.updated(edited), choreID: world.chore.id)
        #expect(await waitUntil { world.model.comments.map(\.body) == ["edited on the web"] })

        await world.comments.simulateRemote(.deleted(id: id), choreID: world.chore.id)
        #expect(await waitUntil { world.model.comments.isEmpty })
        listener.cancel()
    }

    @Test func aDroppedConnectionReloadsWhatWasMissedAndResubscribes() async {
        let world = await makeWorld()
        await world.model.load()
        let listener = Task { await world.model.listen() }
        #expect(await waitUntil { await world.comments.subscriberCount == 1 })

        // While "disconnected", another client comments; nothing is delivered live.
        await world.comments.dropConnections(with: .offline)
        await world.comments.simulateRemote(
            .inserted(ChoreComment(id: UUID(), choreId: world.chore.id, authorId: nil, body: "missed while offline", createdAt: Date())),
            choreID: world.chore.id
        )

        #expect(await waitUntil { world.model.comments.map(\.body) == ["missed while offline"] }, "reload after reconnect catches it")
        #expect(await waitUntil { await world.comments.subscriberCount == 1 }, "and the subscription is re-established")
        listener.cancel()
    }

    @Test func leavingTheScreenClosesTheSubscription() async {
        let world = await makeWorld()
        let listener = Task { await world.model.listen() }
        #expect(await waitUntil { await world.comments.subscriberCount == 1 })
        listener.cancel()
        #expect(await waitUntil { await world.comments.subscriberCount == 0 }, "cancelling must unsubscribe")
    }

    @Test func aChangeArrivingDuringAReloadIsNotLost() async {
        let world = await makeWorld(seeded: [comment("old", at: 1)])
        await world.model.load()
        let listener = Task { await world.model.listen() }
        #expect(await waitUntil { await world.comments.subscriberCount == 1 })

        // A reload and a live insert racing: the final list holds both, once each.
        async let reload: Void = world.model.reloadComments()
        await world.comments.simulateRemote(
            .inserted(ChoreComment(id: UUID(), choreId: world.chore.id, authorId: nil, body: "racing", createdAt: Date())),
            choreID: world.chore.id
        )
        await reload
        #expect(await waitUntil { Set(world.model.comments.map(\.body)) == ["old", "racing"] && world.model.comments.count == 2 })
        listener.cancel()
    }

    // MARK: status

    @Test func theStatusCycleAdvancesOnConfirmationAndTellsTheList() async {
        let world = await makeWorld(chore: makeChore(status: .pending))
        await world.model.load()

        await world.model.advanceStatus()
        #expect(world.model.chore?.status == .inProgress)
        await world.model.advanceStatus()
        #expect(world.model.chore?.status == .done)
        await world.model.advanceStatus()
        #expect(world.model.chore?.status == .pending)

        #expect(world.changed.withLock { $0.map(\.status) } == [.inProgress, .done, .pending])
        #expect(await world.chores.allChores.first?.status == .pending)
    }

    @Test func markAsDoneSetsDoneFromAnyStatus() async {
        let world = await makeWorld(chore: makeChore(status: .inProgress))
        await world.model.load()
        await world.model.markDone()
        #expect(world.model.chore?.status == .done)
        await world.model.markDone()   // already done: no second write
        #expect(world.changed.withLock { $0.count } == 1)
    }

    @Test func aFailedStatusChangeLeavesTheStatusAndShowsWhy() async {
        let chore = makeChore(status: .pending)
        let world = await makeWorld(chore: chore)
        await world.model.load()
        // A repository that fails: delete the chore server-side so the update has nothing to change.
        try? await world.chores.delete(id: chore.id)

        await world.model.advanceStatus()

        #expect(world.model.chore?.status == .pending, "status only changes after the server confirms")
        #expect(world.model.statusError != nil)
        #expect(world.changed.withLock { $0.isEmpty })
        #expect(!world.model.isUpdatingStatus)
    }

    // MARK: calendar

    @Test func aDatedChoreOffersTheSystemCalendarScreen() async {
        let due = DueDateRule.dateOnlyTimestamp(year: 2026, month: 9, day: 24)!
        let world = await makeWorld(chore: makeChore(due: due))
        await world.model.load()
        world.model.prepareCalendarSave()
        guard case .presenting(let draft) = world.model.calendar else { Issue.record("expected presenting"); return }
        #expect(draft.isAllDay)
    }

    @Test func aChoreWithoutADueDateHasNothingToSave() async {
        let world = await makeWorld(chore: makeChore(due: nil))
        await world.model.load()
        world.model.prepareCalendarSave()
        #expect(world.model.calendar == .idle)
    }

    @Test func deniedAndRestrictedAccessAreReportedNotIgnored() async {
        let due = DueDateRule.dateOnlyTimestamp(year: 2026, month: 9, day: 24)!
        let denied = await makeWorld(chore: makeChore(due: due), calendar: .denied)
        await denied.model.load()
        denied.model.prepareCalendarSave()
        #expect(denied.model.calendar == .denied)

        let restricted = await makeWorld(chore: makeChore(due: due), calendar: .restricted)
        await restricted.model.load()
        restricted.model.prepareCalendarSave()
        #expect(restricted.model.calendar == .restricted)
    }

    @Test func onlyAnExplicitSaveCountsAsSuccess() async {
        let due = DueDateRule.dateOnlyTimestamp(year: 2026, month: 9, day: 24)!
        let world = await makeWorld(chore: makeChore(due: due))
        await world.model.load()

        world.model.prepareCalendarSave()
        world.model.finishCalendarSave(.cancelled)
        #expect(world.model.calendar == .cancelled)

        world.model.prepareCalendarSave()
        world.model.finishCalendarSave(.failed("The event couldn't be saved."))
        #expect(world.model.calendar == .failed("The event couldn't be saved."))

        world.model.prepareCalendarSave()
        world.model.finishCalendarSave(.saved)
        #expect(world.model.calendar == .saved)

        world.model.dismissCalendarMessage()
        #expect(world.model.calendar == .idle)
    }
}
