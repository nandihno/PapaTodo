import SwiftUI

enum MainRoute: Hashable {
    case settings
    case detail(UUID)
}

/// The signed-in shell: owns the Home and profile state, applies the profile theme,
/// and refreshes when the app returns to the foreground.
struct MainView: View {
    let user: AppSessionRecord
    let session: AppSession
    let environment: AppEnvironment

    @State private var home: HomeModel
    @State private var profileStore: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(user: AppSessionRecord, environment: AppEnvironment, session: AppSession) {
        self.user = user
        self.session = session
        self.environment = environment
        let expire: @MainActor () -> Void = { [weak session] in session?.handleSessionExpired() }
        _home = State(initialValue: HomeModel(repository: environment.choreRepository, onSessionExpired: expire))
        _profileStore = State(initialValue: ProfileStore(
            userID: user.userId, repository: environment.profileRepository, onSessionExpired: expire
        ))
    }

    var body: some View {
        NavigationStack {
            HomeView(user: user, home: home, profileStore: profileStore, formFactory: formFactory)
                .navigationDestination(for: MainRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(user: user, store: profileStore) {
                            Task { await session.signOut() }
                        }
                    case .detail(let id):
                        detailView(for: id)
                    }
                }
        }
        .tint(tint)
        .task { await home.load() }
        .task { await profileStore.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await home.refresh() }
            }
        }
    }

    private var formFactory: ChoreFormFactory {
        ChoreFormFactory(environment: environment, session: session)
    }

    private func detailView(for id: UUID) -> some View {
        let model = ChoreDetailModel(
            choreID: id,
            seed: home.chores.first { $0.id == id },
            choreRepository: environment.choreRepository,
            commentRepository: environment.commentRepository,
            profileRepository: environment.profileRepository,
            calendarStatus: { CalendarAccess.current() },
            onChoreChanged: { [home] updated in home.upsert(updated) },
            onSessionExpired: { [weak session] in session?.handleSessionExpired() }
        )
        return ChoreDetailView(model: model, formFactory: formFactory) { [home] notice, deleted in
            if deleted { home.remove(id: id) }
            // Show what the save or delete could not finish, as the Home form does.
            home.showNotice(notice)
            Task { await home.refresh() }
        }
    }

    /// The profile theme, unless it would be hard to read as a control color on the
    /// current background, in which case the system default accent is kept.
    private var tint: Color? {
        let hex = profileStore.activeThemeHex
        return ThemeColor.isUsableAsTint(hex, darkMode: colorScheme == .dark) ? Color(hex: hex) : nil
    }
}
