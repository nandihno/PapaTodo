import Foundation

/// Deterministic in-memory `Authenticating` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureAuthenticating: Authenticating {
    private var session: AppSessionRecord?
    private let validEmail: String
    private let validPassword: String
    private var restoreError: DataServiceError?
    private var continuations: [UUID: AsyncStream<AuthEvent>.Continuation] = [:]

    init(
        initialSession: AppSessionRecord? = nil,
        validEmail: String = "family@example.com",
        validPassword: String = "correct-horse",
        restoreError: DataServiceError? = nil
    ) {
        self.session = initialSession
        self.validEmail = validEmail
        self.validPassword = validPassword
        self.restoreError = restoreError
    }

    func currentSession() async throws -> AppSessionRecord? {
        if let restoreError { throw restoreError }
        return session
    }

    func signIn(email: String, password: String) async throws {
        guard email == validEmail, password == validPassword else {
            throw DataServiceError.invalidCredentials
        }
        let record = AppSessionRecord(userId: UUID(), email: email)
        session = record
        broadcast(.signedIn(record))
    }

    func signOut() async throws {
        session = nil
        broadcast(.signedOut)
    }

    /// Test hook: simulates an unrecoverable refresh failure (server-side expiry).
    func expireSession() {
        session = nil
        broadcast(.signedOut)
    }

    /// Test hook: lets a previously failing restore succeed on retry.
    func clearRestoreError() {
        restoreError = nil
    }

    nonisolated func authEvents() -> AsyncStream<AuthEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AuthEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }
        Task { await self.addContinuation(id, continuation) }
        return stream
    }

    private func addContinuation(_ id: UUID, _ continuation: AsyncStream<AuthEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func broadcast(_ event: AuthEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
