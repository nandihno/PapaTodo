/// Auth lifecycle changes surfaced by `Authenticating.authEvents()`.
nonisolated enum AuthEvent: Sendable, Equatable {
    case signedIn(AppSessionRecord)
    /// The session ended. `AppSession` decides whether this was user-initiated
    /// or an unrecoverable expiry.
    case signedOut
}
