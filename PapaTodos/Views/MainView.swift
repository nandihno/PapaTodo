import SwiftUI

enum MainRoute: Hashable {
    case settings
}

/// The signed-in shell: owns the Home and profile state, applies the profile theme,
/// and refreshes when the app returns to the foreground.
struct MainView: View {
    let user: AppSessionRecord
    let session: AppSession

    @State private var home: HomeModel
    @State private var profileStore: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(user: AppSessionRecord, environment: AppEnvironment, session: AppSession) {
        self.user = user
        self.session = session
        let expire: @MainActor () -> Void = { [weak session] in session?.handleSessionExpired() }
        _home = State(initialValue: HomeModel(repository: environment.choreRepository, onSessionExpired: expire))
        _profileStore = State(initialValue: ProfileStore(
            userID: user.userId, repository: environment.profileRepository, onSessionExpired: expire
        ))
    }

    var body: some View {
        NavigationStack {
            HomeView(user: user, home: home, profileStore: profileStore)
                .navigationDestination(for: MainRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(user: user, store: profileStore) {
                            Task { await session.signOut() }
                        }
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

    /// The profile theme, unless it would be hard to read as a control color on the
    /// current background, in which case the system default accent is kept.
    private var tint: Color? {
        let hex = profileStore.activeThemeHex
        return ThemeColor.isUsableAsTint(hex, darkMode: colorScheme == .dark) ? Color(hex: hex) : nil
    }
}
