import Foundation
import Testing
@testable import PapaTodos

@MainActor
struct AppSessionTests {
    private let savedUser = AppSessionRecord(userId: UUID(), email: "family@example.com")

    /// Waits briefly for the session's auth-event observation to apply a change.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startsRestoring() {
        let session = AppSession(authenticating: FixtureAuthenticating())
        #expect(session.phase == .restoring)
    }

    @Test func restoreWithSavedSessionSignsIn() async {
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser))
        await session.restore()
        #expect(session.phase == .signedIn(savedUser))
        #expect(session.currentUser == savedUser)
    }

    @Test func restoreWithoutSessionGoesToSignedOut() async {
        let session = AppSession(authenticating: FixtureAuthenticating())
        await session.restore()
        #expect(session.phase == .signedOut(reason: nil))
    }

    @Test func restoreWithUnrecoverableSessionReturnsToSignInWithExpiryReason() async {
        let auth = FixtureAuthenticating(restoreError: .sessionExpired)
        let session = AppSession(authenticating: auth)
        await session.restore()
        #expect(session.phase == .signedOut(reason: .sessionExpired))
    }

    @Test func offlineRestoreIsRecoverableAndRetrySucceeds() async {
        let auth = FixtureAuthenticating(initialSession: savedUser, restoreError: .offline)
        let session = AppSession(authenticating: auth)
        await session.restore()
        #expect(session.phase == .restoreFailed(message: DataServiceError.offline.errorDescription ?? ""))

        await auth.clearRestoreError()
        await session.restore()
        #expect(session.phase == .signedIn(savedUser))
    }

    @Test func signInWithValidCredentialsSignsIn() async throws {
        let session = AppSession(authenticating: FixtureAuthenticating())
        await session.restore()
        try await session.signIn(email: "family@example.com", password: "correct-horse")
        #expect(session.currentUser?.email == "family@example.com")
    }

    @Test func signInWithBadCredentialsThrowsAndStaysSignedOut() async {
        let session = AppSession(authenticating: FixtureAuthenticating())
        await session.restore()
        await #expect(throws: DataServiceError.invalidCredentials) {
            try await session.signIn(email: "family@example.com", password: "wrong")
        }
        #expect(session.phase == .signedOut(reason: nil))
    }

    @Test func userInitiatedSignOutIsNotReportedAsExpiry() async {
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser))
        await session.restore()
        await session.signOut()
        // Give the auth-event observer time to (incorrectly) flip the reason.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(session.phase == .signedOut(reason: nil))
    }

    @Test func serverSideExpiryWhileSignedInReturnsToSignInWithMessage() async {
        let auth = FixtureAuthenticating(initialSession: savedUser)
        let session = AppSession(authenticating: auth)
        await session.restore()
        #expect(session.currentUser != nil)

        await auth.expireSession()
        await settle { session.phase != .signedIn(savedUser) }
        #expect(session.phase == .signedOut(reason: .sessionExpired))
    }

    @Test func rejectedRequestReturnsToSignInWithMessage() async {
        let session = AppSession(authenticating: FixtureAuthenticating(initialSession: savedUser))
        await session.restore()
        session.handleSessionExpired()
        #expect(session.phase == .signedOut(reason: .sessionExpired))
    }

    @Test func rejectedRequestWhileSignedOutIsIgnored() async {
        let session = AppSession(authenticating: FixtureAuthenticating())
        await session.restore()
        session.handleSessionExpired()
        #expect(session.phase == .signedOut(reason: nil))
    }
}
