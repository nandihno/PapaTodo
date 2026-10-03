import Foundation
import Observation

/// Observable auth/session state (specification.md sections 7.1 and 9.1).
///
/// `phase` is the single source of truth the UI switches on. Restoration,
/// explicit sign-in/out, and SDK-driven auth changes (refresh failure) all
/// funnel through it, so an unrecoverable expiry always lands on sign-in with a
/// message instead of leaving the app in a half-authenticated state.
@Observable
@MainActor
final class AppSession {
    enum Phase: Equatable {
        case restoring
        case signedOut(reason: SignedOutReason?)
        case signedIn(AppSessionRecord)
        /// Restore failed for a recoverable reason (offline, server error). The
        /// saved session may still be valid, so the user retries instead of
        /// being signed out.
        case restoreFailed(message: String)
        /// After a failed restore, browsing the chores saved on this phone for the account whose
        /// sign-in is saved (docs/phase-8-offline-plan.md). Nothing loads until the connection is
        /// back; the first request that renews the sign-in moves the app to `.signedIn`.
        case savedChoresOnly(AppSessionRecord)
    }

    enum SignedOutReason: Equatable {
        case sessionExpired
    }

    private(set) var phase: Phase = .restoring
    /// The account whose sign-in is saved on the phone, when the last restore failed.
    private(set) var savedUserID: UUID?

    var currentUser: AppSessionRecord? {
        switch phase {
        case .signedIn(let record), .savedChoresOnly(let record): record
        default: nil
        }
    }

    /// Erases what this phone keeps for the account (offline chore copies) when a session
    /// ends: sign-out, expiry, or no saved session at all.
    var onSessionEnded: (@MainActor () async -> Void)?

    /// Runs before the session is cleared, so the caller can still make authenticated calls
    /// (for example, unregistering this device from push notifications). Best effort: it gets a
    /// few seconds, and sign-out proceeds regardless of how it ends.
    var beforeSignOut: (@MainActor () async -> Void)?
    var beforeSignOutTimeout: Duration = .seconds(3)

    private let authenticating: any Authenticating
    private var observation: Task<Void, Never>?
    private var isSigningOut = false

    init(authenticating: any Authenticating) {
        self.authenticating = authenticating
    }

    isolated deinit {
        observation?.cancel()
    }

    func restore() async {
        startObservingIfNeeded()
        phase = .restoring
        do {
            if let record = try await authenticating.currentSession() {
                savedUserID = nil
                phase = .signedIn(record)
            } else {
                end(.signedOut(reason: nil))
            }
        } catch DataServiceError.sessionExpired {
            end(.signedOut(reason: .sessionExpired))
        } catch {
            savedUserID = await authenticating.storedUserID()
            phase = .restoreFailed(message: Self.message(for: error))
        }
    }

    /// Opens the saved chores of the account whose sign-in couldn't be restored.
    func browseSavedChores() {
        guard case .restoreFailed = phase, let savedUserID else { return }
        phase = .savedChoresOnly(AppSessionRecord(userId: savedUserID, email: nil))
    }

    func signIn(email: String, password: String) async throws {
        startObservingIfNeeded()
        try await authenticating.signIn(email: email, password: password)
        guard let record = try await authenticating.currentSession() else {
            throw DataServiceError.server
        }
        phase = .signedIn(record)
    }

    func signOut() async {
        isSigningOut = true
        if let hook = beforeSignOut {
            await Self.runWithTimeLimit(beforeSignOutTimeout, hook)
        }
        // Best effort: sign-out must complete locally even if the server call fails.
        try? await authenticating.signOut()
        isSigningOut = false
        end(.signedOut(reason: nil))
    }

    private func end(_ signedOut: Phase) {
        savedUserID = nil
        phase = signedOut
        if let onSessionEnded { Task { await onSessionEnded() } }
    }

    /// Runs `operation`, but stops waiting for it after `limit`. The operation is not cancelled, so a
    /// hung call can't hold up the caller.
    private static func runWithTimeLimit(_ limit: Duration, _ operation: @escaping @MainActor () async -> Void) async {
        let (finished, signal) = AsyncStream<Void>.makeStream()
        Task { @MainActor in
            await operation()
            signal.yield()
        }
        Task {
            try? await Task.sleep(for: limit)
            signal.yield()
        }
        var iterator = finished.makeAsyncIterator()
        _ = await iterator.next()
    }

    /// Called by data screens when a request is rejected as unauthenticated.
    func handleSessionExpired() {
        guard currentUser != nil else { return }
        end(.signedOut(reason: .sessionExpired))
    }

    private func startObservingIfNeeded() {
        guard observation == nil else { return }
        let events = authenticating.authEvents()
        observation = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: AuthEvent) {
        switch event {
        case .signedIn(let record):
            savedUserID = nil
            phase = .signedIn(record)
        case .signedOut:
            guard !isSigningOut, currentUser != nil else { return }
            end(.signedOut(reason: .sessionExpired))
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? DataServiceError)?.errorDescription ?? DataServiceError.server.errorDescription ?? ""
    }
}
