import SwiftUI

/// The Mine / All / Done chore list with search, refresh, and loading/empty/error
/// states. Cards are read-only here; detail and editing arrive in later phases.
struct HomeView: View {
    let user: AppSessionRecord
    @Bindable var home: HomeModel
    let profileStore: ProfileStore
    let environment: AppEnvironment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppSession.self) private var session
    @State private var presentedForm: FormRoute?

    private enum FormRoute: Identifiable {
        case create
        case edit(Chore)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let chore): chore.id.uuidString
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Chores")
            .searchable(text: $home.searchQuery, prompt: "Search chores")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentedForm = .create
                    } label: {
                        Label("New Chore", systemImage: "plus")
                    }
                    .accessibilityIdentifier("home.newChore")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: MainRoute.settings) {
                        ProfileAvatarView(
                            name: profileStore.profile?.fullName ?? user.email,
                            url: profileStore.profile?.avatarURL,
                            size: 32
                        )
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("home.settings")
                }
            }
            .sheet(item: $presentedForm) { route in
                formView(for: route)
            }
    }

    private func formView(for route: FormRoute) -> some View {
        let mode: ChoreFormModel.Mode
        let stored: String?
        switch route {
        case .create:
            mode = .create
            stored = nil
        case .edit(let chore):
            mode = .edit(chore)
            stored = chore.description
        }
        let model = ChoreFormModel(
            mode: mode,
            saveService: ChoreSaveService(
                chores: environment.choreRepository, attachments: environment.attachmentRepository, storage: environment.attachmentStorage
            ),
            deleteService: ChoreDeleteService(chores: environment.choreRepository, storage: environment.attachmentStorage),
            profiles: environment.profileRepository,
            onSessionExpired: { [weak session] in session?.handleSessionExpired() }
        )
        return ChoreFormView(model: model, storedDescription: stored) { notice in
            home.showNotice(notice)
            Task { await home.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch home.loadState {
        case .idle, .loading:
            ProgressView("Loading chores…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("home.loading")
        case .failed(let error):
            ContentUnavailableView {
                Label("Could not load chores", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "")
            } actions: {
                Button("Try Again") { Task { await home.load() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home.retry")
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        let visible = home.visibleChores(currentUserID: user.userId, currentProfile: profileStore.profile)
        return List {
            Section { tabPicker }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            if let notice = home.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .accessibilityIdentifier("home.notice")
                    Button("Dismiss") { home.dismissNotice() }
                }
            }

            if let error = home.refreshError {
                Section {
                    Label("Couldn't refresh. Showing earlier results.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error.errorDescription ?? "").font(.footnote)
                    Button("Try Again") { Task { await home.refresh() } }
                        .accessibilityIdentifier("home.refreshRetry")
                }
            }

            Section {
                if visible.isEmpty {
                    ContentUnavailableView {
                        Text(HomeList.emptyTitle(tab: home.tab, query: home.searchQuery))
                    } description: {
                        Text(HomeList.emptyDetail(query: home.searchQuery))
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("home.empty")
                } else {
                    ForEach(visible) { chore in
                        Button {
                            presentedForm = .edit(chore)
                        } label: {
                            ChoreCardView(chore: chore)
                                // Without this only the drawn text is tappable, not the gaps between it.
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(HomeList.summary(tab: home.tab, query: home.searchQuery, resultCount: visible.count))
                    .textCase(nil)
                    .accessibilityIdentifier("home.summary")
            }
        }
        .refreshable { await home.refresh() }
        .accessibilityIdentifier("home.list")
    }

    /// Segmented control normally; a menu picker at accessibility text sizes, where
    /// segments would truncate.
    @ViewBuilder
    private var tabPicker: some View {
        let picker = Picker("Filter", selection: $home.tab) {
            Text("Mine").tag(HomeTab.mine)
            Text("All").tag(HomeTab.all)
            Text("Done").tag(HomeTab.done)
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).padding(.vertical, 4).accessibilityIdentifier("home.tabs")
        } else {
            picker.pickerStyle(.segmented).padding(.vertical, 4).accessibilityIdentifier("home.tabs")
        }
    }
}
