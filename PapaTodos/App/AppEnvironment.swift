/// Bundles the app's backend-access dependencies behind protocols, per
/// specification.md section 7.4. Phase 1 adds a `.live` factory backed by the
/// Supabase Swift client; until then, `.fixture` is the only environment and
/// keeps the app and its tests fully deterministic.
struct AppEnvironment: Sendable {
    let authenticating: any Authenticating
    let choreRepository: any ChoreRepository
    let commentRepository: any CommentRepository

    static func fixture() -> AppEnvironment {
        AppEnvironment(
            authenticating: FixtureAuthenticating(),
            choreRepository: FixtureChoreRepository(),
            commentRepository: FixtureCommentRepository()
        )
    }
}
