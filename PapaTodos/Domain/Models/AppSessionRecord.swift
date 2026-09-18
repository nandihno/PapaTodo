import Foundation

/// The authenticated user's identity, as needed by app/session/router composition.
nonisolated struct AppSessionRecord: Sendable, Equatable {
    let userId: UUID
    let email: String?
}
