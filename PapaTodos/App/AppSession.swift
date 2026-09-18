import Observation

/// Observable auth/session state. Phase 1 wires this to a real `Authenticating`
/// implementation; for now it only needs to work against the fixture.
@Observable
@MainActor
final class AppSession {
    private(set) var currentUser: AppSessionRecord?

    private let authenticating: any Authenticating

    init(authenticating: any Authenticating) {
        self.authenticating = authenticating
    }

    func restore() async {
        currentUser = try? await authenticating.currentSession()
    }

    func signIn(email: String, password: String) async throws {
        try await authenticating.signIn(email: email, password: password)
        currentUser = try await authenticating.currentSession()
    }

    func signOut() async {
        try? await authenticating.signOut()
        currentUser = nil
    }
}
