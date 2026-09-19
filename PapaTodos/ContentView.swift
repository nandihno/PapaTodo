import SwiftUI

/// Switches on `AppSession.phase`. Phase 2 replaces the signed-in placeholder
/// with the real Home shell.
struct ContentView: View {
    let environment: AppEnvironment
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.phase {
        case .restoring:
            ProgressView("Restoring session…")
        case .signedOut(let reason):
            SignInView(reason: reason)
        case .signedIn(let user):
            SignedInStatusView(user: user, environment: environment)
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
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
    }
}
