import Foundation

/// User-presentable failure categories for auth and data services.
///
/// Live services map SDK/transport errors into these so views never see raw
/// server messages, tokens, or policy detail (specification.md section 11.2).
nonisolated enum DataServiceError: Error, Equatable, LocalizedError {
    case invalidCredentials
    /// A saved session could not be refreshed, or the server rejected the token.
    case sessionExpired
    case offline
    /// The request was cancelled (view left, superseded). Never shown to the user.
    case cancelled
    case server
    /// Row-level security refused the write (for example, photos on a chore the user
    /// neither created nor is assigned to).
    case notPermitted
    /// Only the person who created a chore may delete it.
    case notCreator
    /// A unique value is already taken (for example, a favourite with the same title).
    case duplicate
    /// The row was deleted in the meantime, probably on another device.
    case notFound
    /// The operation exists on the protocol but is intentionally not wired up in
    /// the current phase (for example, chore writes before Phase 3).
    case notAvailableYet

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "That email or password isn't right. Please try again."
        case .sessionExpired:
            "Your session expired. Please sign in again."
        case .offline:
            "You appear to be offline. Check your connection and try again."
        case .cancelled:
            nil
        case .notPermitted:
            "You don't have permission to do that. Photos can only be added or removed on chores you created or are assigned to."
        case .notCreator:
            "Only the person who created this chore can delete it."
        case .duplicate:
            "That name is already in use."
        case .notFound:
            "That item no longer exists. It may have been deleted on another device."
        case .server:
            "Something went wrong talking to the server. Please try again."
        case .notAvailableYet:
            "This isn't available yet."
        }
    }
}
