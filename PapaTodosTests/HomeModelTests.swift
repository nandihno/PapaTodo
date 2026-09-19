import Foundation
import Testing
@testable import PapaTodos

/// A repository whose fetches complete only when the test says so, to force
/// out-of-order responses.
actor ControlledChoreRepository: ChoreRepository {
    private var pending: [CheckedContinuation<[Chore], any Error>] = []

    func fetchChores() async throws -> [Chore] {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }

    var pendingCount: Int { pending.count }

    func complete(_ index: Int, with chores: [Chore]) { pending[index].resume(returning: chores) }
    func fail(_ index: Int, with error: any Error) { pending[index].resume(throwing: error) }

    func fetchChore(id: UUID) async throws -> Chore? { nil }
    func create(_ draft: ChoreDraft) async throws -> Chore { throw DataServiceError.notAvailableYet }
    func update(id: UUID, patch: ChorePatch) async throws -> Chore { throw DataServiceError.notAvailableYet }
    func updateStatus(id: UUID, status: ChoreStatus) async throws {}
    func delete(id: UUID) async throws {}
}

@MainActor
struct HomeModelTests {
    private func makeChore(_ title: String) -> Chore {
        Chore(
            id: UUID(), title: title, description: nil, assignedTo: FixtureData.currentUserID, createdBy: nil,
            status: .pending, dueDate: nil, imageURL: nil, createdAt: Date(), updatedAt: Date()
        )
    }

    private func waitForPending(_ count: Int, _ repository: ControlledChoreRepository) async {
        for _ in 0..<500 where await repository.pendingCount < count {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func loadPopulatesChores() async {
        let model = HomeModel(repository: FixtureChoreRepository())
        #expect(model.loadState == .idle)
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.chores.count == 5)
    }

    @Test func firstLoadFailureShowsErrorAndRetrySucceeds() async {
        let model = HomeModel(repository: FixtureChoreRepository(failFirstFetches: 1))
        await model.load()
        #expect(model.loadState == .failed(.offline))
        #expect(model.chores.isEmpty)

        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.chores.count == 5)
    }

    @Test func failedRefreshKeepsExistingChoresAndReportsTheError() async {
        let controlled = ControlledChoreRepository()
        let live = HomeModel(repository: controlled)
        async let first: Void = live.load()
        await waitForPending(1, controlled)
        await controlled.complete(0, with: [makeChore("kept")])
        await first
        #expect(live.chores.map(\.title) == ["kept"])

        async let second: Void = live.refresh()
        await waitForPending(2, controlled)
        await controlled.fail(1, with: DataServiceError.offline)
        await second

        #expect(live.chores.map(\.title) == ["kept"])
        #expect(live.loadState == .loaded)
        #expect(live.refreshError == .offline)
        #expect(!live.isRefreshing)
    }

    @Test func slowOlderResponseNeverOverwritesANewerOne() async {
        let controlled = ControlledChoreRepository()
        let model = HomeModel(repository: controlled)

        async let older: Void = model.load()
        await waitForPending(1, controlled)
        async let newer: Void = model.refresh()
        await waitForPending(2, controlled)

        await controlled.complete(1, with: [makeChore("newer")])
        await newer
        #expect(model.chores.map(\.title) == ["newer"])

        await controlled.complete(0, with: [makeChore("older")])
        await older
        #expect(model.chores.map(\.title) == ["newer"])
        #expect(model.loadState == .loaded)
        #expect(!model.isRefreshing)
    }

    @Test func sessionExpiryIsForwardedNotShownAsAnError() async {
        var expired = 0
        let controlled = ControlledChoreRepository()
        let model = HomeModel(repository: controlled, onSessionExpired: { expired += 1 })
        async let load: Void = model.load()
        await waitForPending(1, controlled)
        await controlled.fail(0, with: DataServiceError.sessionExpired)
        await load
        #expect(expired == 1)
    }

    @Test func cancellationIsNotAUserFacingError() async {
        let controlled = ControlledChoreRepository()
        let model = HomeModel(repository: controlled)
        async let load: Void = model.load()
        await waitForPending(1, controlled)
        await controlled.fail(0, with: DataServiceError.cancelled)
        await load
        #expect(model.refreshError == nil)
        if case .failed = model.loadState { Issue.record("cancellation must not produce a failed state") }
    }

    @Test func visibleChoresFollowTabAndSearch() async {
        let model = HomeModel(repository: FixtureChoreRepository())
        await model.load()
        let me = FixtureData.currentUserID

        model.tab = .mine
        #expect(Set(model.visibleChores(currentUserID: me, currentProfile: nil).map(\.title))
                == ["Take out recycling", "Water the garden"])
        model.tab = .done
        #expect(model.visibleChores(currentUserID: me, currentProfile: nil).map(\.title) == ["Fold laundry"])
        model.tab = .all
        model.searchQuery = "alex"   // assignee/creator name
        #expect(!model.visibleChores(currentUserID: me, currentProfile: nil).isEmpty)
        model.searchQuery = "zzz"
        #expect(model.visibleChores(currentUserID: me, currentProfile: nil).isEmpty)
    }
}

@MainActor
struct ProfileStoreTests {
    let me = FixtureData.currentUserID

    /// Records which profile ids were written, to prove the store never touches another row.
    actor SpyProfileRepository: ProfileRepository {
        private(set) var writtenIDs: [UUID] = []
        private let inner = FixtureProfileRepository()
        func fetchProfile(id: UUID) async throws -> Profile? { try await inner.fetchProfile(id: id) }
        func fetchProfiles() async throws -> [ProfileSummary] { try await inner.fetchProfiles() }
        func updateAvatarURL(id: UUID, to url: URL?) async throws -> Profile {
            writtenIDs.append(id); return try await inner.updateAvatarURL(id: id, to: url)
        }
        func updateThemeColor(id: UUID, to hex: String) async throws -> Profile {
            writtenIDs.append(id); return try await inner.updateThemeColor(id: id, to: hex)
        }
    }

    @Test func loadsOwnProfile() async {
        let store = ProfileStore(userID: me, repository: FixtureProfileRepository())
        await store.load()
        #expect(store.profile?.fullName == "Family Tester")
        #expect(store.savedThemeHex == ThemeColor.defaultHex)
    }

    @Test func validAvatarSavesAndEmptyClears() async {
        let store = ProfileStore(userID: me, repository: FixtureProfileRepository())
        await store.load()

        await store.saveAvatar("https://example.com/me.png")
        #expect(store.profile?.avatarURL?.absoluteString == "https://example.com/me.png")
        #expect(store.avatarSave == .saved("Avatar saved."))

        await store.saveAvatar("  ")
        #expect(store.profile?.avatarURL == nil)
        #expect(store.avatarSave == .saved("Avatar cleared."))
    }

    @Test func invalidAvatarIsRejectedBeforeAnyWrite() async {
        let spy = SpyProfileRepository()
        let store = ProfileStore(userID: me, repository: spy)
        await store.saveAvatar("ftp://nope")
        #expect(store.avatarSave == .failed("Enter a valid http or https image URL."))
        #expect(await spy.writtenIDs.isEmpty)
    }

    @Test func writesOnlyEverTargetTheSignedInUsersRow() async {
        let spy = SpyProfileRepository()
        let store = ProfileStore(userID: me, repository: spy)
        await store.saveAvatar("https://example.com/me.png")
        await store.saveTheme("#4F46E5")
        #expect(await spy.writtenIDs == [me, me])
    }

    @Test func themePreviewAppliesUntilSavedOrDiscarded() async {
        let store = ProfileStore(userID: me, repository: FixtureProfileRepository())
        await store.load()
        #expect(store.activeThemeHex == "#008F81")

        store.previewTheme("#c2410c")
        #expect(store.activeThemeHex == "#C2410C")
        #expect(store.savedThemeHex == "#008F81")

        store.discardThemePreview()
        #expect(store.activeThemeHex == "#008F81")

        store.previewTheme("#C2410C")
        await store.saveTheme("#C2410C")
        #expect(store.savedThemeHex == "#C2410C")
        #expect(store.activeThemeHex == "#C2410C")
        #expect(store.themeSave == .saved("Theme saved."))
    }

    @Test func invalidThemeIsIgnoredOrRejected() async {
        let store = ProfileStore(userID: me, repository: FixtureProfileRepository())
        store.previewTheme("nope")
        #expect(store.previewThemeHex == nil)
        await store.saveTheme("nope")
        #expect(store.themeSave == .failed("Choose a valid accent color."))
    }

    @Test func saveFailureIsReportedWithoutLeakingDetail() async {
        let store = ProfileStore(userID: me, repository: FixtureProfileRepository(failure: .offline))
        await store.saveTheme("#4F46E5")
        #expect(store.themeSave == .failed(DataServiceError.offline.errorDescription ?? ""))
    }

    @Test func sessionExpiryDuringASaveIsForwarded() async {
        var expired = 0
        let store = ProfileStore(
            userID: me, repository: FixtureProfileRepository(failure: .sessionExpired),
            onSessionExpired: { expired += 1 }
        )
        await store.saveAvatar("https://example.com/me.png")
        #expect(expired == 1)
        // Expiry is handled by signing out: no error banner, and no stuck spinner.
        #expect(store.avatarSave == .idle)
    }
}

struct TintContrastTests {
    @Test func paleThemesAreNotUsedToTintInLightMode() {
        #expect(!ThemeColor.isUsableAsTint("#FFFF00", darkMode: false))
        #expect(ThemeColor.isUsableAsTint("#4F46E5", darkMode: false))
        #expect(ThemeColor.isUsableAsTint("#008F81", darkMode: false) == ThemeColor.isUsableAsTint("#008F81", darkMode: false))
    }

    @Test func veryDarkThemesAreNotUsedToTintInDarkMode() {
        #expect(!ThemeColor.isUsableAsTint("#000000", darkMode: true))
        #expect(ThemeColor.isUsableAsTint("#FFFF00", darkMode: true))
    }

    @Test func allSuggestedColorsAreUsableInLightMode() {
        for hex in ThemeColor.suggestedHexes {
            #expect(ThemeColor.isUsableAsTint(hex, darkMode: false), "\(hex) should tint in light mode")
        }
    }
}
