import Auth
import Foundation
import Supabase

/// `Authenticating` backed by Supabase Auth.
nonisolated struct SupabaseAuthenticating: Authenticating {
    let client: SupabaseClient

    /// `auth.session` refreshes an expired access token and throws when the
    /// refresh token is unusable, which maps to `.sessionExpired`.
    func currentSession() async throws -> AppSessionRecord? {
        guard client.auth.currentSession != nil else { return nil }
        do {
            let session = try await client.auth.session
            return AppSessionRecord(session)
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func authEvents() -> AsyncStream<AuthEvent> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in changes {
                    switch event {
                    case .signedIn, .tokenRefreshed:
                        if let session { continuation.yield(.signedIn(AppSessionRecord(session))) }
                    case .signedOut, .userDeleted:
                        continuation.yield(.signedOut)
                    default:
                        // .initialSession is handled by currentSession(); the
                        // rest don't change whether the user is signed in.
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension AppSessionRecord {
    nonisolated init(_ session: Session) {
        self.init(userId: session.user.id, email: session.user.email)
    }
}
