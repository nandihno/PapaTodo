import Foundation
import Testing
@testable import PapaTodos

/// Takes a long time to "send", to prove the action that caused it never waits.
actor SlowNotifier: NotificationDispatching {
    private(set) var finished = 0
    func notify(_ event: PushEvent, choreID: UUID) async {
        try? await Task.sleep(for: .seconds(2))
        finished += 1
    }
}

@MainActor
struct NotificationDispatchTests {
    let me = FixtureData.currentUserID
    let other = FixtureData.otherUserID

    private func chore(assignedTo: UUID? = nil, status: ChoreStatus = .pending) -> Chore {
        Chore(
            id: UUID(), title: "Notify me", description: "d", assignedTo: assignedTo, createdBy: FixtureData.currentUserID,
            status: status, dueDate: nil, imageURL: nil, createdAt: Date(), updatedAt: Date()
        )
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    private func formModel(
        mode: ChoreFormModel.Mode, chores: FixtureChoreRepository, notifier: any NotificationDispatching
    ) -> ChoreFormModel {
        let faults = FaultInjector()
        let rows = FixtureAttachmentRepository(faults: faults, chores: chores)
        let storage = FixtureAttachmentStorage(faults: faults)
        return ChoreFormModel(
            mode: mode,
            saveService: ChoreSaveService(chores: chores, attachments: rows, storage: storage),
            deleteService: ChoreDeleteService(chores: chores, storage: storage),
            profiles: FixtureProfileRepository(), notifier: notifier
        )
    }

    // MARK: saves

    @Test func creatingAChoreWithAnAssigneeSendsChoreAssigned() async throws {
        let chores = FixtureChoreRepository(chores: [])
        let notifier = FixtureNotificationDispatcher()
        let model = formModel(mode: .create, chores: chores, notifier: notifier)
        model.title = "Assigned"
        model.assignedTo = other

        await model.save()

        let created = try #require(await chores.allChores.first)
        #expect(await waitUntil { await notifier.sent == [.init(event: .choreAssigned, choreID: created.id)] })
    }

    @Test func creatingAnUnassignedChoreSendsNothing() async throws {
        let chores = FixtureChoreRepository(chores: [])
        let notifier = FixtureNotificationDispatcher()
        let model = formModel(mode: .create, chores: chores, notifier: notifier)
        model.title = "Nobody's"

        await model.save()

        #expect(model.didFinish)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await notifier.sent.isEmpty)
    }

    @Test func editingAChoreSendsChoreUpdated() async throws {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let notifier = FixtureNotificationDispatcher()
        let model = formModel(mode: .edit(existing), chores: chores, notifier: notifier)
        model.title = "Renamed"

        await model.save()

        #expect(await waitUntil { await notifier.sent == [.init(event: .choreUpdated, choreID: existing.id)] })
    }

    @Test func savingAnEditThatChangedNothingSendsNothing() async {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let notifier = FixtureNotificationDispatcher()
        let model = formModel(mode: .edit(existing), chores: chores, notifier: notifier)

        await model.save()

        #expect(model.didFinish)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await notifier.sent.isEmpty, "no change means nothing to tell anyone")
    }

    @Test func aFailedSaveSendsNothing() async {
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(chores: [], faults: faults)
        let notifier = FixtureNotificationDispatcher()
        let model = ChoreFormModel(
            mode: .create,
            saveService: ChoreSaveService(
                chores: chores, attachments: FixtureAttachmentRepository(faults: faults, chores: chores),
                storage: FixtureAttachmentStorage(faults: faults)
            ),
            deleteService: ChoreDeleteService(chores: chores, storage: FixtureAttachmentStorage(faults: faults)),
            profiles: FixtureProfileRepository(), notifier: notifier
        )
        model.title = "Will fail"
        model.assignedTo = other
        await faults.arm(.createChore, error: .offline)

        await model.save()

        #expect(!model.didFinish)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await notifier.sent.isEmpty)
    }

    @Test func aSlowNotifierNeverDelaysOrFailsTheSave() async {
        let chores = FixtureChoreRepository(chores: [])
        let model = formModel(mode: .create, chores: chores, notifier: SlowNotifier())
        model.title = "Quick save"
        model.assignedTo = other

        let started = ContinuousClock.now
        await model.save()

        #expect(model.didFinish)
        #expect(model.errorMessage == nil)
        #expect(ContinuousClock.now - started < .seconds(1), "the save did not wait for the two-second notification")
    }

    // MARK: detail screen

    private func detailModel(
        for chore: Chore, chores: FixtureChoreRepository, comments: FixtureCommentRepository, notifier: any NotificationDispatching
    ) -> ChoreDetailModel {
        ChoreDetailModel(
            choreID: chore.id, seed: chore, choreRepository: chores, commentRepository: comments,
            profileRepository: FixtureProfileRepository(), notifier: notifier
        )
    }

    @Test func changingTheStatusSendsStatusChanged() async {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let notifier = FixtureNotificationDispatcher()
        let model = detailModel(for: existing, chores: chores, comments: FixtureCommentRepository(), notifier: notifier)

        await model.markDone()

        #expect(await waitUntil { await notifier.sent == [.init(event: .statusChanged, choreID: existing.id)] })
    }

    @Test func aFailedStatusChangeSendsNothing() async {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let notifier = FixtureNotificationDispatcher()
        let model = detailModel(for: existing, chores: chores, comments: FixtureCommentRepository(), notifier: notifier)
        try? await chores.delete(id: existing.id)   // so the update fails

        await model.markDone()

        try? await Task.sleep(for: .milliseconds(100))
        #expect(await notifier.sent.isEmpty)
    }

    @Test func postingACommentSendsCommentCreated() async {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let notifier = FixtureNotificationDispatcher()
        let model = detailModel(for: existing, chores: chores, comments: FixtureCommentRepository(), notifier: notifier)
        model.commentDraft = "hello"

        await model.sendComment()

        #expect(await waitUntil { await notifier.sent == [.init(event: .commentCreated, choreID: existing.id)] })
    }

    @Test func aFailedCommentSendsNothingAndKeepsTheDraft() async {
        let existing = chore(assignedTo: other)
        let chores = FixtureChoreRepository(chores: [existing])
        let comments = FixtureCommentRepository()
        let notifier = FixtureNotificationDispatcher()
        let model = detailModel(for: existing, chores: chores, comments: comments, notifier: notifier)
        await comments.failNextAdd(with: .offline)
        model.commentDraft = "won't post"

        await model.sendComment()

        #expect(model.commentDraft == "won't post")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await notifier.sent.isEmpty)
    }

    @Test func aSlowNotifierNeverDelaysAComment() async {
        let existing = chore(assignedTo: other)
        let model = detailModel(
            for: existing, chores: FixtureChoreRepository(chores: [existing]), comments: FixtureCommentRepository(), notifier: SlowNotifier()
        )
        model.commentDraft = "quick"

        let started = ContinuousClock.now
        await model.sendComment()

        #expect(model.comments.count == 1)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}
