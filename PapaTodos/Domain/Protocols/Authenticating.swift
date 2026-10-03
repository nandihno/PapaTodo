import Foundation

nonisolated protocol Authenticating: Sendable {
    func currentSession() async throws -> AppSessionRecord?
    /// The account whose sign-in is saved on the phone, read without the network, even if the
    /// session has expired. Used to offer that account's saved chores when a restore fails offline.
    func storedUserID() async -> UUID?
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    /// Auth lifecycle changes after the initial restore (sign-in, sign-out, expiry).
    func authEvents() -> AsyncStream<AuthEvent>
}
