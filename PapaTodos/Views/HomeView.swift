import SwiftUI

/// The Mine / All / Done chore list with search, refresh, and loading/empty/error
/// states. Cards are read-only here; detail and editing arrive in later phases.
struct HomeView: View {
    let user: AppSessionRecord
    @Bindable var home: HomeModel
    let profileStore: ProfileStore
    let formFactory: ChoreFormFactory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PushRegistrationModel.self) private var push
    @Environment(FavouritesStore.self) private var favourites
    @State private var presentedForm: FormRoute?

    private enum FormRoute: Identifiable {
        /// A new chore, pre-filled from a favourite when one is given.
        case create(ChoreTemplate?)
        var id: String {
            switch self {
            case .create(let template): template.map { "create-\($0.id)" } ?? "create"
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Chores")
            .searchable(text: $home.searchQuery, prompt: "Search chores")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Tap for a blank chore; touch and hold to start from a favourite.
                    Menu {
                        Button {
                            presentedForm = .create(nil)
                        } label: {
                            Label("Blank Chore", systemImage: "square.and.pencil")
                        }
                        if !favourites.templates.isEmpty {
                            Section("Favourites") {
                                ForEach(favourites.templates.prefix(5)) { template in
                                    Button {
                                        presentedForm = .create(template)
                                    } label: {
                                        Label(template.title, systemImage: "star")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("New Chore", systemImage: "plus")
                    } primaryAction: {
                        presentedForm = .create(nil)
                    }
                    .accessibilityHint(favourites.templates.isEmpty ? "" : "Touch and hold to start from a favourite.")
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
        let model = formFactory.makeModel(mode: .create)
        if case .create(let template?) = route { model.apply(template, asBaseline: true) }
        return ChoreFormView(model: model) { notice, _ in
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

            if push.shouldShowHomePrompt {
                Section {
                    Label("Get notified about your chores", systemImage: "bell.badge")
                        .font(.headline)
                        // On the heading, not the Section: a container's identifier hides its children's.
                        .accessibilityIdentifier("home.notificationPrompt")
                    Text("We'll let you know when a chore is assigned to you, changed, commented on, or completed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Turn On Notifications") { Task { await push.enableNotifications() } }
                        .disabled(push.isRequestingPermission)
                        .accessibilityIdentifier("home.enableNotifications")
                    Button("Not Now") { push.dismissPrompt() }
                        .accessibilityIdentifier("home.dismissNotificationPrompt")
                }
            }

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
                        NavigationLink(value: MainRoute.detail(chore.id)) {
                            ChoreCardView(chore: chore)
                                // Without this only the drawn text is tappable, not the gaps between it.
                                .contentShape(Rectangle())
                        }
                        // On the link (the row) so each chore is one element, not two.
                        .accessibilityIdentifier("chore.card")
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
