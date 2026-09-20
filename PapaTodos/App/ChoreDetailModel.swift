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
@Observable
@MainActor
final class ChoreDetailModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case notFound
        case failed(DataServiceError)
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
    var commentDraft = ""

    private let choreRepository: any ChoreRepository
    private let commentRepository: any CommentRepository
    private let profileRepository: any ProfileRepository
    private let calendarStatus: @Sendable () -> CalendarAccessStatus
    private let onChoreChanged: @MainActor (Chore) -> Void
    private let onSessionExpired: @MainActor () -> Void
    private let retryDelays: [Duration]

    private var bufferedChanges: [CommentChange]?
    private var latestReload = 0

    init(
        choreID: UUID,
        seed: Chore? = nil,
        choreRepository: any ChoreRepository,
        commentRepository: any CommentRepository,
        profileRepository: any ProfileRepository,
        calendarStatus: @escaping @Sendable () -> CalendarAccessStatus = { .available },
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)],
        onChoreChanged: @escaping @MainActor (Chore) -> Void = { _ in },
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.choreID = choreID
        self.chore = seed
        self.loadState = seed == nil ? .loading : .loaded
        self.choreRepository = choreRepository
        self.commentRepository = commentRepository
        self.profileRepository = profileRepository
        self.calendarStatus = calendarStatus
        self.retryDelays = retryDelays
        self.onChoreChanged = onChoreChanged
        self.onSessionExpired = onSessionExpired
    }

    var comments: [ChoreComment] { thread.comments }
    var canSendComment: Bool { chore != nil && !isSendingComment && CommentBody.validated(commentDraft) != nil }

    func author(of comment: ChoreComment) -> ProfileSummary? {
        comment.authorId.flatMap { people[$0] }
    }

    // MARK: loading

    /// Loads the chore, comments and people together. Safe to call again to refresh.
    func load() async {
        async let profiles: Void = loadPeople()
        async let choreResult: Void = loadChore()
        async let commentsResult: Void = reloadComments()
        _ = await (profiles, choreResult, commentsResult)
    }

    private func loadChore() async {
        do {
            if let fetched = try await choreRepository.fetchChore(id: choreID) {
                chore = fetched
                loadState = .loaded
            } else {
                chore = nil
                loadState = .notFound
            }
        } catch {
            handle(error) { failure in
                // Keep showing what we already have if a refresh fails.
                if chore == nil { loadState = .failed(failure) }
            }
        }
    }

    private func loadPeople() async {
        if let fetched = try? await profileRepository.fetchProfiles() {
            people = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }
    }

    /// Reloads comments (initial load, foregrounding, after reconnecting). Changes that
    /// arrive during the fetch are re-applied on top of the snapshot.
    func reloadComments() async {
        latestReload += 1
        let request = latestReload
        bufferedChanges = []
        do {
            let fetched = try await commentRepository.fetchComments(choreID: choreID)
            guard request == latestReload else { return }
            thread.replace(with: fetched)
            for change in bufferedChanges ?? [] { thread.apply(change) }
            commentsError = nil
        } catch {
            guard request == latestReload else { return }
            handle(error) { commentsError = $0.errorDescription }
        }
        if request == latestReload { bufferedChanges = nil }
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
    }

    // MARK: comments

    func sendComment() async {
        guard !isSendingComment, let body = CommentBody.validated(commentDraft) else { return }
        isSendingComment = true
        commentsError = nil
        do {
            let created = try await commentRepository.addComment(choreID: choreID, body: body)
            receive(.inserted(created))
            commentDraft = ""
        } catch {
            // The draft stays so the user can retry.
            handle(error) { commentsError = $0.errorDescription }
        }
        isSendingComment = false
    }

    // MARK: status

    /// Waits for the server to confirm before changing what's shown.
    func setStatus(_ status: ChoreStatus) async {
        guard let current = chore, !isUpdatingStatus, status != current.status else { return }
        isUpdatingStatus = true
        statusError = nil
        do {
            try await choreRepository.updateStatus(id: choreID, status: status)
            var updated = current
            updated.status = status
            updated.updatedAt = Date()
            chore = updated
            onChoreChanged(updated)
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
