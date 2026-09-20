import Foundation

/// Bundles the app's backend-access dependencies behind protocols, per
/// specification.md section 7.4. `.live` talks to Supabase; `.fixture` keeps the
/// app and its tests fully deterministic.
struct AppEnvironment: Sendable {
    let authenticating: any Authenticating
    let choreRepository: any ChoreRepository
    let commentRepository: any CommentRepository
    let profileRepository: any ProfileRepository
    let attachmentRepository: any AttachmentRepository
    let attachmentStorage: any AttachmentStorage

    static func live(configuration: AppConfiguration) -> AppEnvironment {
        let client = SupabaseClientFactory.make(configuration: configuration)
        return AppEnvironment(
            authenticating: SupabaseAuthenticating(client: client),
            choreRepository: SupabaseChoreRepository(client: client),
            commentRepository: SupabaseCommentRepository(client: client),
            profileRepository: SupabaseProfileRepository(client: client),
            attachmentRepository: SupabaseAttachmentRepository(client: client),
            attachmentStorage: SupabaseAttachmentStorage(client: client)
        )
    }

    static func fixture(
        authenticating: any Authenticating = FixtureAuthenticating(),
        failFirstChoreFetches: Int = 0,
        remoteComment: Bool = false,
        storageRefusesDeletes: Bool = false
    ) -> AppEnvironment {
        let faults = FaultInjector()
        let chores = FixtureChoreRepository(failFirstFetches: failFirstChoreFetches, faults: faults)
        let remote = remoteComment ? ChoreComment(
            id: UUID(), choreId: FixtureData.recyclingID, authorId: FixtureData.otherUserID,
            body: "Posted from another device", createdAt: Date()
        ) : nil
        let comments = FixtureCommentRepository(comments: FixtureData.comments(), remoteCommentOnFirstSubscribe: remote)
        return AppEnvironment(
            authenticating: authenticating,
            choreRepository: chores,
            commentRepository: comments,
            profileRepository: FixtureProfileRepository(),
            attachmentRepository: FixtureAttachmentRepository(faults: faults, chores: chores),
            attachmentStorage: FixtureAttachmentStorage(faults: faults, allowsDelete: !storageRefusesDeletes)
        )
    }
}
