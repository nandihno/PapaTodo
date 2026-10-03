import SwiftUI

/// Switches on `AppSession.phase`.
struct ContentView: View {
    let environment: AppEnvironment
    @Environment(AppSession.self) private var session
    /// How many chores are saved on the phone for the account whose restore failed.
    @State private var savedCount = 0

    var body: some View {
        switch session.phase {
        case .restoring:
            ProgressView("Restoring session…")
        case .signedOut(let reason):
            SignInView(reason: reason)
        case .signedIn(let user):
            MainView(user: user, environment: environment, session: session)
                .id(user.userId)
                .preferredColorScheme(UITestHooks.forcedColorScheme)
        case .savedChoresOnly(let user):
            MainView(user: user, environment: environment, session: session, savedChoresOnly: true)
                .id(user.userId)
                .preferredColorScheme(UITestHooks.forcedColorScheme)
        case .restoreFailed(let message):
            ContentUnavailableView {
                Label("Can't restore session", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await session.restore() }
                }
                .buttonStyle(.borderedProminent)
                if savedCount > 0 {
                    Button("View Saved Chores (\(savedCount))") {
                        session.browseSavedChores()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Shows the chores you opened most recently, as they were then.")
                    .accessibilityIdentifier("restore.viewSaved")
                }
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
            .task(id: session.savedUserID) {
                guard let userID = session.savedUserID else { savedCount = 0; return }
                savedCount = await environment.choreCache.entries(userID: userID).count
            }
        }
    }
}
