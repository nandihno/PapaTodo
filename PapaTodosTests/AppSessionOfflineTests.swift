import Foundation
import Testing
@testable import PapaTodos

/// Saved chores after a failed restore, and erasing them when a session ends
/// (docs/phase-8-offline-plan.md).
@MainActor
struct AppSessionOfflineTests {
    private let savedUser = AppSessionRecord(userId: FixtureData.currentUserID, email: "family@example.com")

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test func anOfflineRestoreRemembersWhoseSignInIsSavedAndCanBrowseTheirChores() async {
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser, restoreError: .offline))
        await session.restore()
        #expect(session.savedUserID == savedUser.userId)
        #expect(session.currentUser == nil)

        session.browseSavedChores()
        #expect(session.phase == .savedChoresOnly(AppSessionRecord(userId: savedUser.userId, email: nil)))
        #expect(session.currentUser?.userId == savedUser.userId)
    }

    @Test func withNoSavedSignInThereIsNothingToBrowse() async {
        let session = AppSession(authenticating: FixtureAuthenticating(restoreError: .offline))
        await session.restore()
        #expect(session.savedUserID == nil)
        session.browseSavedChores()
        #expect(session.phase == .restoreFailed(message: DataServiceError.offline.errorDescription ?? ""))
    }

    @Test func aLaterSuccessfulRestoreLeavesTheSavedChores() async {
        let auth = FixtureAuthenticating(initialSession: savedUser, restoreError: .offline)
        let session = AppSession(authenticating: auth)
        await session.restore()
        session.browseSavedChores()

        await auth.clearRestoreError()
        await session.restore()
        #expect(session.phase == .signedIn(savedUser))
        #expect(session.savedUserID == nil)
    }

    @Test func signingOutErasesTheSavedChores() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        await FixtureData.seedSavedChores(into: cache)
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser))
        session.onSessionEnded = { await cache.removeAll() }
        await session.restore()
        #expect(await cache.entries(userID: savedUser.userId).count == 2)

        await session.signOut()
        #expect(await waitUntil { await cache.entries(userID: savedUser.userId).isEmpty })
    }

    @Test func expiryWhileBrowsingSavedChoresSignsOutAndErasesThem() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        await FixtureData.seedSavedChores(into: cache)
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser, restoreError: .offline))
        session.onSessionEnded = { await cache.removeAll() }
        await session.restore()
        session.browseSavedChores()

        session.handleSessionExpired()
        #expect(session.phase == .signedOut(reason: .sessionExpired))
        #expect(await waitUntil { await cache.entries(userID: savedUser.userId).isEmpty })
    }

    @Test func aRestoreThatFindsNoSessionErasesLeftoverCopies() async {
        let ended = LockedState(0)
        let session = AppSession(authenticating: FixtureAuthenticating())
        session.onSessionEnded = { ended.withLock { $0 += 1 } }
        await session.restore()
        #expect(await waitUntil { ended.withLock { $0 } == 1 })
    }

    @Test func signingInOrAFailedRestoreKeepsTheSavedChores() async throws {
        let ended = LockedState(0)
        let offline = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser, restoreError: .offline))
        offline.onSessionEnded = { ended.withLock { $0 += 1 } }
        await offline.restore()

        let fresh = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser))
        fresh.onSessionEnded = { ended.withLock { $0 += 1 } }
        await fresh.restore()

        try? await Task.sleep(for: .milliseconds(50))
        #expect(ended.withLock { $0 } == 0)
    }
}
