import Foundation

/// Bundles the app's backend-access dependencies behind protocols, per
/// specification.md section 7.4. `.live` talks to Supabase; `.fixture` keeps the
/// app and its tests fully deterministic.
struct AppEnvironment: Sendable {
    let authenticating: any Authenticating
    let choreRepository: any ChoreRepository
    let commentRepository: any CommentRepository
    let profileRepository: any ProfileRepository
    let choreTemplateRepository: any ChoreTemplateRepository
    let attachmentRepository: any AttachmentRepository
    let attachmentStorage: any AttachmentStorage
    /// Offline copies of recently viewed chores (docs/phase-8-offline-plan.md).
    let choreCache: any ChoreCache
    /// Chore photos for the detail screen: saved copies first, then downloads.
    let photoStore: ChorePhotoStore
    let deviceRegistry: any NotificationDeviceRegistering
    let notifier: any NotificationDispatching
    let notificationPermission: any NotificationPermissionProviding

    static func live(configuration: AppConfiguration) -> AppEnvironment {
        let client = SupabaseClientFactory.make(configuration: configuration)
        let cache = SQLiteChoreCache(fileURL: SQLiteChoreCache.defaultFileURL)
        return AppEnvironment(
            authenticating: SupabaseAuthenticating(client: client),
            choreRepository: SupabaseChoreRepository(client: client),
            commentRepository: SupabaseCommentRepository(client: client),
            profileRepository: SupabaseProfileRepository(client: client),
            choreTemplateRepository: SupabaseChoreTemplateRepository(client: client),
            attachmentRepository: SupabaseAttachmentRepository(client: client),
            attachmentStorage: SupabaseAttachmentStorage(client: client),
            choreCache: cache,
            photoStore: ChorePhotoStore(cache: cache, downloader: URLSessionPhotoDownloader()),
            deviceRegistry: SupabaseNotificationDeviceRegistry(
                client: client, environment: configuration.apnsEnvironment, bundleIdentifier: configuration.bundleIdentifier
            ),
            notifier: SupabaseNotificationDispatcher(client: client),
            notificationPermission: SystemNotificationPermission()
        )
    }

    static func fixture(
        authenticating: any Authenticating = FixtureAuthenticating(),
        failFirstChoreFetches: Int = 0,
        remoteComment: Bool = false,
        storageRefusesDeletes: Bool = false,
        noFavourites: Bool = false,
        offline: Bool = false,
        notificationStatus: NotificationAuthorization = .notDetermined
    ) -> AppEnvironment {
        let faults = FaultInjector()
        let cache = SQLiteChoreCache(fileURL: nil)
        if offline {
            // Finishes long before a UI test has typed its way through sign-in.
            Task { await FixtureData.seedSavedChores(into: cache) }
        }
        let chores = FixtureChoreRepository(failFirstFetches: failFirstChoreFetches, alwaysOffline: offline, faults: faults)
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
            choreTemplateRepository: FixtureChoreTemplateRepository(templates: noFavourites ? [] : FixtureData.templates),
            attachmentRepository: FixtureAttachmentRepository(faults: faults, chores: chores),
            attachmentStorage: FixtureAttachmentStorage(faults: faults, allowsDelete: !storageRefusesDeletes),
            choreCache: cache,
            photoStore: ChorePhotoStore(cache: cache, downloader: FixturePhotoDownloader(failing: offline)),
            deviceRegistry: FixtureNotificationDeviceRegistry(),
            notifier: FixtureNotificationDispatcher(),
            notificationPermission: FixtureNotificationPermission(current: notificationStatus)
        )
    }
}
