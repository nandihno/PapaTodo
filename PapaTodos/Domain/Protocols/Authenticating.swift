nonisolated protocol Authenticating: Sendable {
    func currentSession() async throws -> AppSessionRecord?
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    /// Auth lifecycle changes after the initial restore (sign-in, sign-out, expiry).
    func authEvents() -> AsyncStream<AuthEvent>
}
