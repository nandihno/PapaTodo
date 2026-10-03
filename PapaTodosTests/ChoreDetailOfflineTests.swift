import Foundation
import Testing
@testable import PapaTodos

/// Offline copies on the detail screen (docs/phase-8-offline-plan.md).
@MainActor
struct ChoreDetailOfflineTests {
    let me = FixtureData.currentUserID
    let savedTime = Date(timeIntervalSince1970: 1_000_000)

    struct World {
        let chore: Chore
        let chores: FixtureChoreRepository
        let comments: FixtureCommentRepository
        let faults: FaultInjector
        let cache: SQLiteChoreCache
        let model: ChoreDetailModel
    }

    private func makeChore(title: String = "Latest title", id: UUID = UUID()) -> Chore {
        Chore(
            id: id, title: title, description: "d", assignedTo: me, createdBy: me, status: .pending,
            dueDate: nil, imageURL: nil, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeWorld(
        inRepository: Bool = true, seedModel: Bool = false, savedCopy: CachedChore? = nil, choreID: UUID = UUID()
    ) async -> World {
        let chore = makeChore(id: choreID)
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(chores: inRepository ? [chore] : [], faults: faults)
        let comments = FixtureCommentRepository(comments: [
            ChoreComment(id: UUID(), choreId: chore.id, authorId: FixtureData.otherUserID, body: "live comment", createdAt: Date())
        ])
        let cache = SQLiteChoreCache(fileURL: nil)
        if let savedCopy { await cache.save(savedCopy, userID: me) }
        let model = ChoreDetailModel(
            choreID: chore.id, seed: seedModel ? chore : nil,
            choreRepository: chores, commentRepository: comments, profileRepository: FixtureProfileRepository(),
            cache: cache, userID: me
        )
        return World(chore: chore, chores: chores, comments: comments, faults: faults, cache: cache, model: model)
    }

    private func savedCopy(of id: UUID, title: String = "Saved title") -> CachedChore {
        CachedChore(
            chore: makeChore(title: title, id: id),
            comments: [ChoreComment(id: UUID(), choreId: id, authorId: FixtureData.otherUserID, body: "saved comment", createdAt: savedTime)],
            people: [ProfileSummary(id: FixtureData.otherUserID, fullName: "Alex (saved)", avatarURL: nil)],
            savedAt: savedTime
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

    // MARK: saving

    @Test func aConfirmedFetchIsSavedForOffline() async {
        let world = await makeWorld()
        await world.model.load()

        #expect(world.model.freshness == .upToDate)
        #expect(!world.model.isReadOnly)
        let saved = await waitUntil { await world.cache.entry(choreID: world.chore.id, userID: me) != nil }
        #expect(saved)
        let entry = await world.cache.entry(choreID: world.chore.id, userID: me)
        #expect(entry?.chore.title == "Latest title")
        #expect(entry?.comments.map(\.body) == ["live comment"])
        #expect(entry?.people.contains { $0.id == FixtureData.otherUserID } == true)
    }

    @Test func aSuccessfulRefreshIsConfirmedBrieflyAndAFailedOneIsNot() async {
        let chore = makeChore()
        let faults = FaultInjector()
        let model = ChoreDetailModel(
            choreID: chore.id,
            choreRepository: FixtureChoreRepository(chores: [chore], faults: faults),
            commentRepository: FixtureCommentRepository(comments: []), profileRepository: FixtureProfileRepository(),
            confirmationDuration: .milliseconds(50)
        )
        await model.load()
        #expect(model.confirmsUpToDate)
        #expect(await waitUntil { !model.confirmsUpToDate })

        await faults.arm(.fetchChore, error: .offline)
        await model.load()
        #expect(!model.confirmsUpToDate)
        #expect(model.freshness == .unreachable(savedAt: nil))
    }

    @Test func aFailedCommentLoadDoesNotSaveAHalfFreshCopy() async {
        let world = await makeWorld()
        await world.comments.failNextFetches(1)
        await world.model.load()

        #expect(world.model.freshness == .upToDate)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await world.cache.entry(choreID: world.chore.id, userID: me) == nil)
    }

    @Test func aStatusChangeUpdatesTheSavedCopy() async {
        let world = await makeWorld()
        await world.model.load()
        await world.model.setStatus(.done)

        let updated = await waitUntil { await world.cache.entry(choreID: world.chore.id, userID: me)?.chore.status == .done }
        #expect(updated)
    }

    // MARK: offline

    @Test func withoutAConnectionTheSavedCopyShowsReadOnly() async {
        let id = UUID()
        let world = await makeWorld(savedCopy: savedCopy(of: id), choreID: id)
        await world.faults.arm(.fetchChore, error: .offline)
        await world.comments.failNextFetches(1)
        await world.model.load()

        #expect(world.model.loadState == .loaded)
        #expect(world.model.chore?.title == "Saved title")
        #expect(world.model.comments.map(\.body) == ["saved comment"])
        #expect(world.model.author(of: world.model.comments[0]) != nil)
        #expect(world.model.freshness == .unreachable(savedAt: savedTime))
        #expect(world.model.isReadOnly)
    }

    @Test func aSavedCopyBlocksStatusChangesAndComments() async throws {
        let id = UUID()
        let world = await makeWorld(savedCopy: savedCopy(of: id), choreID: id)
        await world.faults.arm(.fetchChore, error: .offline)
        await world.model.load()

        await world.model.setStatus(.done)
        #expect(world.model.chore?.status == .pending)
        #expect(try await world.chores.fetchChore(id: id)?.status == .pending)

        world.model.commentDraft = "hello"
        #expect(!world.model.canSendComment)
        await world.model.sendComment()
        #expect(try await world.comments.fetchComments(choreID: id).map(\.body) == ["live comment"])
    }

    @Test func refreshingOnceBackOnlineReplacesTheSavedCopy() async {
        let id = UUID()
        let world = await makeWorld(savedCopy: savedCopy(of: id), choreID: id)
        await world.faults.arm(.fetchChore, error: .offline)
        await world.model.load()
        #expect(world.model.isReadOnly)

        await world.model.load()
        #expect(world.model.chore?.title == "Latest title")
        #expect(world.model.comments.map(\.body) == ["live comment"])
        #expect(world.model.freshness == .upToDate)
        #expect(!world.model.isReadOnly)
        let replaced = await waitUntil { await world.cache.entry(choreID: id, userID: me)?.chore.title == "Latest title" }
        #expect(replaced)
    }

    @Test func readingTheSavedCopyCountsAsViewingIt() async {
        let id = UUID()
        let world = await makeWorld(savedCopy: savedCopy(of: id, title: "Opened offline"), choreID: id)
        let other = UUID()
        await world.cache.save(savedCopy(of: other, title: "Saved later"), userID: me)

        await world.faults.arm(.fetchChore, error: .offline)
        await world.model.load()
        #expect(await world.cache.entries(userID: me).map(\.chore.title) == ["Opened offline", "Saved later"])
    }

    @Test func noConnectionAndNoSavedCopyStillFails() async {
        let world = await makeWorld()
        await world.faults.arm(.fetchChore, error: .offline)
        await world.model.load()

        #expect(world.model.loadState == .failed(.offline))
        #expect(world.model.freshness == .unreachable(savedAt: nil))
    }

    @Test func aChoreFromTheHomeListStaysEditableWhenTheRefreshFails() async {
        let world = await makeWorld(seedModel: true)
        await world.faults.arm(.fetchChore, error: .offline)
        await world.model.load()

        #expect(world.model.freshness == .unreachable(savedAt: nil))
        #expect(!world.model.isReadOnly)
    }

    @Test func aDeletedChoreLosesItsSavedCopy() async {
        let id = UUID()
        let world = await makeWorld(inRepository: false, savedCopy: savedCopy(of: id), choreID: id)
        await world.model.load()

        #expect(world.model.loadState == .notFound)
        #expect(await world.cache.entry(choreID: id, userID: me) == nil)
    }
}
