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
    }

    enum SignedOutReason: Equatable {
        case sessionExpired
    }

    private(set) var phase: Phase = .restoring

    var currentUser: AppSessionRecord? {
        if case .signedIn(let record) = phase { record } else { nil }
    }

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
                phase = .signedIn(record)
            } else {
                phase = .signedOut(reason: nil)
            }
        } catch DataServiceError.sessionExpired {
            phase = .signedOut(reason: .sessionExpired)
        } catch {
            phase = .restoreFailed(message: Self.message(for: error))
        }
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
        phase = .signedOut(reason: nil)
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
        guard case .signedIn = phase else { return }
        phase = .signedOut(reason: .sessionExpired)
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
            phase = .signedIn(record)
        case .signedOut:
            guard !isSigningOut, case .signedIn = phase else { return }
            phase = .signedOut(reason: .sessionExpired)
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? DataServiceError)?.errorDescription ?? DataServiceError.server.errorDescription ?? ""
    }
}
