import Foundation
import Testing
@testable import PapaTodos

/// Home's "Saved for offline" fallback (docs/phase-8-offline-plan.md).
@MainActor
struct HomeOfflineTests {
    let me = FixtureData.currentUserID

    private func saved(_ title: String, savedAt: Date = Date(timeIntervalSince1970: 0)) -> CachedChore {
        let chore = Chore(
            id: UUID(), title: title, description: nil, assignedTo: me, createdBy: me, status: .pending,
            dueDate: nil, imageURL: nil, createdAt: savedAt, updatedAt: savedAt
        )
        return CachedChore(chore: chore, comments: [], people: [], savedAt: savedAt)
    }

    private func makeModel(failFirstFetches: Int = 0, alwaysOffline: Bool = false, cache: SQLiteChoreCache) -> HomeModel {
        HomeModel(
            repository: FixtureChoreRepository(failFirstFetches: failFirstFetches, alwaysOffline: alwaysOffline),
            cache: cache, userID: me
        )
    }

    @Test func aFailedFirstLoadOffersTheSavedChoresMostRecentlyViewedFirst() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        await cache.save(saved("Older"), userID: me)
        await cache.save(saved("Newer"), userID: me)
        let home = makeModel(alwaysOffline: true, cache: cache)

        await home.load()
        #expect(home.loadState == .failed(.offline))
        #expect(home.savedChores.map(\.title) == ["Newer", "Older"])
    }

    @Test func nothingSavedMeansThePlainErrorAsBefore() async {
        let home = makeModel(alwaysOffline: true, cache: SQLiteChoreCache(fileURL: nil))
        await home.load()
        #expect(home.loadState == .failed(.offline))
        #expect(home.savedChores.isEmpty)
    }

    @Test func anotherAccountsSavedChoresAreNeverOffered() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        await cache.save(saved("Someone else's"), userID: FixtureData.otherUserID)
        let home = makeModel(alwaysOffline: true, cache: cache)
        await home.load()
        #expect(home.savedChores.isEmpty)
    }

    @Test func retryingKeepsTheSavedListOnScreenAndSuccessReplacesIt() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        await cache.save(saved("Saved"), userID: me)
        let home = makeModel(failFirstFetches: 1, cache: cache)

        await home.load()
        #expect(home.savedChores.count == 1)

        // The retry doesn't swap the saved list for the full-screen loader.
        let retry = Task { await home.load() }
        var spins = 0
        while !home.isRefreshing && home.loadState != .loaded && spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        #expect(home.loadState != .loading)
        await retry.value

        #expect(home.loadState == .loaded)
        #expect(home.savedChores.isEmpty)
        #expect(home.chores.count == FixtureChoreRepository.sampleChores.count)
    }
}
