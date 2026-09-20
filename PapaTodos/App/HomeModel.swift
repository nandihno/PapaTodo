import Foundation
import Observation

/// State behind the Home screen: the loaded chores, the selected tab and search
/// text, and the load/refresh lifecycle.
///
/// Every load takes a request number; only the newest request may write results, so
/// a slow earlier response (for example a foreground refresh racing a pull-to-refresh)
/// can never overwrite a newer one (specification.md section 9.2). A failed refresh
/// keeps the chores already on screen and reports the error separately instead of
/// blanking the list.
@Observable
@MainActor
final class HomeModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// The first load failed, so there is nothing to show yet.
        case failed(DataServiceError)
    }

    private(set) var chores: [Chore] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isRefreshing = false
    /// A refresh failed but earlier results are still displayed.
    private(set) var refreshError: DataServiceError?

    /// A note after a form save/delete that completed with a caveat (for example, photo
    /// files that could not be removed from storage).
    private(set) var notice: String?

    var tab: HomeTab = .mine
    var searchQuery = ""

    private let repository: any ChoreRepository
    private let onSessionExpired: @MainActor () -> Void
    private var latestRequest = 0

    init(repository: any ChoreRepository, onSessionExpired: @escaping @MainActor () -> Void = {}) {
        self.repository = repository
        self.onSessionExpired = onSessionExpired
    }

    /// Reflects a change made on the detail screen (such as a new status) immediately, before the
    /// next refresh, so the list never disagrees with the screen the user just left.
    func upsert(_ chore: Chore) {
        if let index = chores.firstIndex(where: { $0.id == chore.id }) {
            var merged = chore
            // The detail copy may lack embedded rows the list already has.
            merged.assignedProfile = chore.assignedProfile ?? chores[index].assignedProfile
            merged.createdProfile = chore.createdProfile ?? chores[index].createdProfile
            merged.attachments = chore.attachments ?? chores[index].attachments
            chores[index] = merged
        }
    }

    func remove(id: UUID) {
        chores.removeAll { $0.id == id }
    }

    func showNotice(_ message: String?) {
        notice = message
    }

    func dismissNotice() {
        notice = nil
    }

    func visibleChores(currentUserID: UUID, currentProfile: Profile?, now: Date = Date()) -> [Chore] {
        HomeList.visibleChores(
            from: chores, tab: tab, query: searchQuery,
            currentUserID: currentUserID, currentProfile: currentProfile, now: now
        )
    }

    /// First load, or a retry after the first load failed: shows the full-screen loader.
    func load() async {
        await perform(showFullLoader: chores.isEmpty)
    }

    /// Pull-to-refresh and foreground refresh: keeps the list visible while fetching.
    func refresh() async {
        await perform(showFullLoader: false)
    }

    private func perform(showFullLoader: Bool) async {
        latestRequest += 1
        let request = latestRequest

        if showFullLoader {
            loadState = .loading
        } else {
            isRefreshing = true
        }
        refreshError = nil

        do {
            let fetched = try await repository.fetchChores()
            guard request == latestRequest else { return }
            chores = fetched
            loadState = .loaded
            isRefreshing = false
        } catch {
            guard request == latestRequest else { return }
            isRefreshing = false
            let failure = (error as? DataServiceError) ?? (error is CancellationError ? .cancelled : .server)
            switch failure {
            case .cancelled:
                // The view went away or the task was cancelled: not a user-facing error.
                if loadState == .loading { loadState = chores.isEmpty ? .idle : .loaded }
            case .sessionExpired:
                onSessionExpired()
            default:
                if chores.isEmpty && loadState != .loaded {
                    loadState = .failed(failure)
                } else {
                    loadState = .loaded
                    refreshError = failure
                }
            }
        }
    }
}
