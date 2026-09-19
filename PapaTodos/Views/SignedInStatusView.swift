import SwiftUI

/// Phase 1 read-only proof that the signed-in session can read shared data
/// under RLS. Deliberately has no create/update/delete UI; Phase 2 replaces it.
struct SignedInStatusView: View {
    let user: AppSessionRecord
    let environment: AppEnvironment

    @Environment(AppSession.self) private var session
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(profile: Profile?, choreCount: Int)
        case failed(DataServiceError)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Signed in as", value: user.email ?? "Unknown email")
                }
                Section("Shared data") {
                    switch state {
                    case .loading:
                        ProgressView("Loading…")
                    case .loaded(let profile, let choreCount):
                        LabeledContent("Profile", value: profile?.fullName ?? "No profile name")
                        LabeledContent("Chores visible", value: "\(choreCount)")
                            .accessibilityIdentifier("status.choreCount")
                    case .failed(let error):
                        Text(error.errorDescription ?? "")
                        Button("Try Again") { Task { await load() } }
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                    .accessibilityIdentifier("status.signOut")
                }
            }
            .navigationTitle("Papa Tools")
            .refreshable { await load() }
        }
        .task(id: user.userId) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            async let profile = environment.profileRepository.fetchProfile(id: user.userId)
            async let chores = environment.choreRepository.fetchChores()
            let (loadedProfile, loadedChores) = try await (profile, chores)
            state = .loaded(profile: loadedProfile, choreCount: loadedChores.count)
        } catch is CancellationError {
            // A newer load superseded this one; ignore the late result.
        } catch DataServiceError.sessionExpired {
            session.handleSessionExpired()
        } catch {
            state = .failed((error as? DataServiceError) ?? .server)
        }
    }
}
