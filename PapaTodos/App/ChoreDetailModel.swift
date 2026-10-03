import Foundation
import Observation

enum CalendarAccessStatus: Sendable, Equatable {
    /// Not asked yet, or granted: the system add-event screen can be shown.
    case available
    case denied
    case restricted
}

/// State behind the chore detail screen: the chore, its comments (kept in step with
/// Realtime), status changes, and the calendar hand-off.
///
/// Comment reconciliation: the list is a `CommentThread`, so the same comment arriving from
/// the insert response, the live stream and a reload appears once. Changes that arrive while a
/// reload is in flight are buffered and re-applied on top of the fresh snapshot, so neither a
/// reload nor the stream can lose a comment the other saw.
///
/// Offline copies (docs/phase-8-offline-plan.md): the phone's saved copy is shown first while
/// Supabase is asked for the latest. Each confirmed fetch replaces the saved copy. While only
/// the saved copy is showing, changes are blocked.
@Observable
@MainActor
final class ChoreDetailModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case notFound
        case failed(DataServiceError)
    }

    /// How current the chore on screen is; drives the status banner.
    enum Freshness: Equatable {
        /// Asking Supabase for the latest.
        case checking
        /// The last refresh succeeded.
        case upToDate
        /// The last refresh failed. `savedAt` is when the phone's saved copy was fetched, or
        /// nil when there is none (the chore shown came from the Home list).
        case unreachable(savedAt: Date?)
    }

    private enum ChoreFetch {
        case fetched
        case notFound
        case failed
    }

    enum CalendarState: Equatable {
        case idle
        /// The system add-event screen should be shown for this event.
        case presenting(CalendarEventDraft)
        case saved
        case cancelled
        case denied
        case restricted
        case failed(String)
    }

    let choreID: UUID
    private(set) var chore: Chore?
    private(set) var loadState: LoadState = .loading
    private(set) var thread = CommentThread()
    private(set) var people: [UUID: ProfileSummary] = [:]
    private(set) var commentsError: String?
    private(set) var isUpdatingStatus = false
    private(set) var statusError: String?
    private(set) var isSendingComment = false
    private(set) var isReconnecting = false
    private(set) var calendar: CalendarState = .idle
    private(set) var freshness: Freshness = .checking
    /// The chore on screen came from the phone's saved copy and Supabase hasn't confirmed it yet.
    private(set) var isShowingSavedCopy = false
    /// True for a moment after a refresh succeeds, so the screen can confirm it.
    private(set) var confirmsUpToDate = false
    var commentDraft = ""

    private let choreRepository: any ChoreRepository
    private let commentRepository: any CommentRepository
    private let profileRepository: any ProfileRepository
    private let notifier: (any NotificationDispatching)?
    private let cache: (any ChoreCache)?
    private let photos: ChorePhotoStore?
    private let userID: UUID?
    private let calendarStatus: @Sendable () -> CalendarAccessStatus
    private let onChoreChanged: @MainActor (Chore) -> Void
    private let onSessionExpired: @MainActor () -> Void
    private let retryDelays: [Duration]

    private var bufferedChanges: [CommentChange]?
    private var latestReload = 0
    /// When the phone's saved copy was last fetched from Supabase.
    private var savedAt: Date?
    private var persisting: Task<Void, Never>?
    private var confirmationReset: Task<Void, Never>?
    private let confirmationDuration: Duration

    /// - Parameters:
    ///   - cache: where offline copies are kept; nil turns offline copies off.
    ///   - photos: where the screen's photos come from; nil shows none.
    ///   - userID: the signed-in account the copies belong to.
    init(
        choreID: UUID,
        seed: Chore? = nil,
        choreRepository: any ChoreRepository,
        commentRepository: any CommentRepository,
        profileRepository: any ProfileRepository,
        notifier: (any NotificationDispatching)? = nil,
        cache: (any ChoreCache)? = nil,
        photos: ChorePhotoStore? = nil,
        userID: UUID? = nil,
        calendarStatus: @escaping @Sendable () -> CalendarAccessStatus = { .available },
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)],
        confirmationDuration: Duration = .seconds(2),
        onChoreChanged: @escaping @MainActor (Chore) -> Void = { _ in },
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.choreID = choreID
        self.chore = seed
        self.loadState = seed == nil ? .loading : .loaded
        self.choreRepository = choreRepository
        self.commentRepository = commentRepository
        self.profileRepository = profileRepository
        self.notifier = notifier
        self.cache = cache
        self.photos = photos
        self.userID = userID
        self.calendarStatus = calendarStatus
        self.retryDelays = retryDelays
        self.confirmationDuration = confirmationDuration
        self.onChoreChanged = onChoreChanged
        self.onSessionExpired = onSessionExpired
    }

    var comments: [ChoreComment] { thread.comments }
    /// Changes wait until Supabase has confirmed the chore; a saved copy may be out of date.
    var isReadOnly: Bool { isShowingSavedCopy }
    var canSendComment: Bool {
        chore != nil && !isReadOnly && !isSendingComment && CommentBody.validated(commentDraft) != nil
    }

    func author(of comment: ChoreComment) -> ProfileSummary? {
        comment.authorId.flatMap { people[$0] }
    }

    // MARK: loading

    /// Shows the saved copy (if any), then loads the chore, comments and people together and
    /// saves them as the new copy. Safe to call again to refresh.
    func load() async {
        await showSavedCopy()
        freshness = .checking
        confirmsUpToDate = false
        async let profiles: Void = loadPeople()
        async let choreResult = loadChore()
        async let commentsResult = reloadComments()
        let (_, outcome, commentsLoaded) = await (profiles, choreResult, commentsResult)
        await finishRefresh(outcome, commentsLoaded: commentsLoaded)
    }

    /// A chore handed over by the Home list is newer than the saved copy, so then the copy only
    /// fills in comments and people until the fetch returns.
    private func showSavedCopy() async {
        guard let cache, let userID, let saved = await cache.entry(choreID: choreID, userID: userID) else { return }
        savedAt = saved.savedAt
        if people.isEmpty {
            people = Dictionary(saved.people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if thread.comments.isEmpty { thread.replace(with: saved.comments) }
        if chore == nil {
            chore = saved.chore
            loadState = .loaded
            isShowingSavedCopy = true
        }
    }

    private func loadChore() async -> ChoreFetch {
        do {
            if let fetched = try await choreRepository.fetchChore(id: choreID) {
                chore = fetched
                loadState = .loaded
                return .fetched
            }
            chore = nil
            loadState = .notFound
            return .notFound
        } catch {
            handle(error) { failure in
                // Keep showing what we already have if a refresh fails.
                if chore == nil { loadState = .failed(failure) }
            }
            return .failed
        }
    }

    private func finishRefresh(_ outcome: ChoreFetch, commentsLoaded: Bool) async {
        switch outcome {
        case .fetched:
            isShowingSavedCopy = false
            freshness = .upToDate
            confirmUpToDate()
            // A copy with fresh chore details but stale comments would claim to be newer than it is.
            if commentsLoaded { persist() }
        case .notFound:
            // Deleted, or no longer visible to this account: the copy must go too.
            isShowingSavedCopy = false
            freshness = .upToDate
            savedAt = nil
            if let cache, let userID { await cache.remove(choreID: choreID, userID: userID) }
        case .failed:
            freshness = .unreachable(savedAt: savedAt)
            // Reading the saved copy counts as viewing it, so it isn't the next one evicted.
            if savedAt != nil, let cache, let userID { await cache.markViewed(choreID: choreID, userID: userID) }
        }
    }

    private func confirmUpToDate() {
        confirmsUpToDate = true
        confirmationReset?.cancel()
        let duration = confirmationDuration
        confirmationReset = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.confirmsUpToDate = false
        }
    }

    /// Saves what's on screen as the phone's copy, once Supabase has confirmed it. Saves run one
    /// after another, so an older snapshot never overwrites a newer one.
    private func persist() {
        guard let cache, let userID, let chore, freshness == .upToDate else { return }
        let entry = CachedChore(chore: chore, comments: thread.comments, people: Array(people.values), savedAt: Date())
        savedAt = entry.savedAt
        let previous = persisting
        let save = Task {
            await previous?.value
            await cache.save(entry, userID: userID)
        }
        persisting = save
        // Photos come after the save: the cache only keeps photos of chores it holds.
        if let photos, !entry.photoURLs.isEmpty {
            Task {
                await save.value
                await photos.prefetch(entry, userID: userID)
            }
        }
    }

    /// One of this chore's photos: the phone's saved copy when there is one, otherwise a download.
    func photoData(for url: URL) async -> Data? {
        await photos?.data(for: url, choreID: choreID, userID: userID)
    }

    private func loadPeople() async {
        if let fetched = try? await profileRepository.fetchProfiles() {
            people = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }
    }

    /// Reloads comments (initial load, foregrounding, after reconnecting). Changes that
    /// arrive during the fetch are re-applied on top of the snapshot. Returns whether this
    /// reload succeeded.
    @discardableResult
    func reloadComments() async -> Bool {
        latestReload += 1
        let request = latestReload
        bufferedChanges = []
        var succeeded = false
        do {
            let fetched = try await commentRepository.fetchComments(choreID: choreID)
            guard request == latestReload else { return false }
            thread.replace(with: fetched)
            for change in bufferedChanges ?? [] { thread.apply(change) }
            commentsError = nil
            succeeded = true
        } catch {
            guard request == latestReload else { return false }
            handle(error) { commentsError = $0.errorDescription }
        }
        bufferedChanges = nil
        // During load() this is skipped (still checking); load saves once the chore is confirmed.
        if succeeded { persist() }
        return succeeded
    }

    // MARK: live comments

    /// Keeps the comment list live until cancelled: subscribes, applies changes, and if the
    /// connection drops reloads (to catch anything missed) and resubscribes with backoff.
    /// Cancelling the calling task, when the screen closes, closes the subscription.
    func listen() async {
        var attempt = 0
        while !Task.isCancelled {
            let stream = commentRepository.changes(choreID: choreID)
            if attempt > 0 { await reloadComments() }
            do {
                for try await change in stream {
                    isReconnecting = false
                    attempt = 0
                    receive(change)
                }
            } catch {
                if let failure = error as? DataServiceError, failure == .sessionExpired {
                    onSessionExpired()
                    return
                }
            }
            guard !Task.isCancelled else { break }
            isReconnecting = true
            let delay = retryDelays[min(attempt, retryDelays.count - 1)]
            attempt += 1
            try? await Task.sleep(for: delay)
        }
        isReconnecting = false
    }

    private func receive(_ change: CommentChange) {
        thread.apply(change)
        if bufferedChanges != nil { bufferedChanges?.append(change) }
        persist()
    }

    // MARK: comments

    func sendComment() async {
        guard !isSendingComment, !isReadOnly, let body = CommentBody.validated(commentDraft) else { return }
        isSendingComment = true
        commentsError = nil
        do {
            let created = try await commentRepository.addComment(choreID: choreID, body: body)
            receive(.inserted(created))
            commentDraft = ""
            notify(.commentCreated)
        } catch {
            // The draft stays so the user can retry.
            handle(error) { commentsError = $0.errorDescription }
        }
        isSendingComment = false
    }

    // MARK: status

    /// Waits for the server to confirm before changing what's shown.
    func setStatus(_ status: ChoreStatus) async {
        guard let current = chore, !isReadOnly, !isUpdatingStatus, status != current.status else { return }
        isUpdatingStatus = true
        statusError = nil
        do {
            try await choreRepository.updateStatus(id: choreID, status: status)
            var updated = current
            updated.status = status
            updated.updatedAt = Date()
            chore = updated
            onChoreChanged(updated)
            persist()
            notify(.statusChanged)
        } catch {
            handle(error) { statusError = $0.errorDescription }
        }
        isUpdatingStatus = false
    }

    func advanceStatus() async {
        guard let status = chore?.status else { return }
        await setStatus(status.next)
    }

    func markDone() async {
        await setStatus(.done)
    }

    // MARK: calendar

    func prepareCalendarSave() {
        guard let chore, let draft = CalendarEventDraft.make(for: chore) else { return }
        switch calendarStatus() {
        case .denied: calendar = .denied
        case .restricted: calendar = .restricted
        case .available: calendar = .presenting(draft)
        }
    }

    /// Only an explicit `saved` from the system screen counts as success.
    func finishCalendarSave(_ result: CalendarSaveResult) {
        switch result {
        case .saved: calendar = .saved
        case .cancelled: calendar = .cancelled
        case .failed(let message): calendar = .failed(message)
        }
    }

    func dismissCalendarMessage() {
        calendar = .idle
    }

    /// Fire and forget: the change already succeeded, so a notification problem must not affect it.
    private func notify(_ event: PushEvent) {
        guard let notifier else { return }
        let id = choreID
        Task { await notifier.notify(event, choreID: id) }
    }

    // MARK: errors

    private func handle(_ error: any Error, assign: (DataServiceError) -> Void) {
        let failure = (error as? DataServiceError) ?? .server
        switch failure {
        case .cancelled: break
        case .sessionExpired: onSessionExpired()
        default: assign(failure)
        }
    }
}

enum CalendarSaveResult: Equatable, Sendable {
    case saved
    case cancelled
    case failed(String)
}
