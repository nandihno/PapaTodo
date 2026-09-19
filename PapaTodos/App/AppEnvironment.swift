/// Bundles the app's backend-access dependencies behind protocols, per
/// specification.md section 7.4. `.live` talks to Supabase; `.fixture` keeps the
/// app and its tests fully deterministic.
struct AppEnvironment: Sendable {
    let authenticating: any Authenticating
    let choreRepository: any ChoreRepository
    let commentRepository: any CommentRepository
    let profileRepository: any ProfileRepository

    static func live(configuration: AppConfiguration) -> AppEnvironment {
        let client = SupabaseClientFactory.make(configuration: configuration)
        return AppEnvironment(
            authenticating: SupabaseAuthenticating(client: client),
            choreRepository: SupabaseChoreRepository(client: client),
            commentRepository: SupabaseCommentRepository(client: client),
            profileRepository: SupabaseProfileRepository(client: client)
        )
    }

    static func fixture(
        authenticating: any Authenticating = FixtureAuthenticating(),
        failFirstChoreFetches: Int = 0
    ) -> AppEnvironment {
        AppEnvironment(
            authenticating: authenticating,
            choreRepository: FixtureChoreRepository(failFirstFetches: failFirstChoreFetches),
            commentRepository: FixtureCommentRepository(),
            profileRepository: FixtureProfileRepository()
        )
    }
}
