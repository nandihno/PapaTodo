import Foundation

/// Deterministic in-memory `Authenticating` fake for tests and previews.
/// Never talks to Supabase — see specification.md section 7.4.
actor FixtureAuthenticating: Authenticating {
    private var session: AppSessionRecord?
    private let validEmail: String
    private let validPassword: String

    init(
        initialSession: AppSessionRecord? = nil,
        validEmail: String = "family@example.com",
        validPassword: String = "correct-horse"
    ) {
        self.session = initialSession
        self.validEmail = validEmail
        self.validPassword = validPassword
    }

    func currentSession() async throws -> AppSessionRecord? {
        session
    }

    func signIn(email: String, password: String) async throws {
        guard email == validEmail, password == validPassword else {
            throw AuthenticationError.invalidCredentials
        }
        session = AppSessionRecord(userId: UUID(), email: email)
    }

    func signOut() async throws {
        session = nil
    }

    enum AuthenticationError: Error {
        case invalidCredentials
    }
}
