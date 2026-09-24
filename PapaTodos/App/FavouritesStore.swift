import Foundation
import Observation

/// The shared favourite chores: loading them, and adding, editing, deleting and reordering.
///
/// One store lives for the signed-in session (owned by `MainView`) and is read by Settings,
/// the New Chore form, the Home + menu and the chore detail screen. There is no Realtime
/// subscription; each of those screens asks for a refresh when it appears.
@Observable
@MainActor
final class FavouritesStore {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(DataServiceError)
    }

    enum SaveOutcome: Equatable {
        case saved(ChoreTemplate)
        /// Another favourite already has this title; `existing` is it, if it's in the list.
        case duplicate(existing: ChoreTemplate?)
        case failed(String)
    }

    private(set) var templates: [ChoreTemplate] = []
    private(set) var loadState: LoadState = .idle
    /// A failed delete or reorder, shown on the list until dismissed or the next change.
    private(set) var listError: String?
    /// Family members, for the assignee picker and names in the list.
    private(set) var people: [ProfileSummary] = []

    private let repository: any ChoreTemplateRepository
    private let profiles: any ProfileRepository
    private let onSessionExpired: @MainActor () -> Void

    init(
        repository: any ChoreTemplateRepository,
        profiles: any ProfileRepository,
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.repository = repository
        self.profiles = profiles
        self.onSessionExpired = onSessionExpired
    }

    func loadPeople() async {
        if let fetched = try? await profiles.fetchProfiles() { people = fetched }
    }

    func name(of personID: UUID?) -> String? {
        guard let personID else { return nil }
        return people.first { $0.id == personID }?.fullName ?? "Family member"
    }

    func load() async {
        if templates.isEmpty { loadState = .loading }
        do {
            templates = try await repository.fetchTemplates()
            loadState = .loaded
        } catch {
            let failure = Self.failure(error)
            if failure == .sessionExpired { onSessionExpired() }
            // Keep showing what we had; only an empty list reports the failure.
            if failure != .cancelled, templates.isEmpty { loadState = .failed(failure) }
        }
    }

    func template(id: UUID) -> ChoreTemplate? {
        templates.first { $0.id == id }
    }

    /// The favourite whose title collides with `title`, other than `excluding`.
    func existing(titled title: String, excluding: UUID? = nil) -> ChoreTemplate? {
        templates.first { $0.id != excluding && FavouriteRules.sameTitle($0.title, title) }
    }

    func suggestions(for query: String) -> [ChoreTemplate] {
        FavouriteRules.suggestions(for: query, in: templates)
    }

    // MARK: writes

    /// Adds a favourite, or updates `id` when given. A title clash is caught locally when the
    /// clashing favourite is in the list, and by the database otherwise.
    func save(_ draft: ChoreTemplateDraft, id: UUID? = nil) async -> SaveOutcome {
        var draft = draft
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { return .failed("Title is required.") }
        if let clash = existing(titled: draft.title, excluding: id) { return .duplicate(existing: clash) }
        listError = nil
        do {
            let saved: ChoreTemplate
            if let id {
                saved = try await repository.update(id: id, with: draft)
                if let index = templates.firstIndex(where: { $0.id == id }) { templates[index] = saved }
            } else {
                saved = try await repository.create(draft, sortOrder: FavouriteRules.nextSortOrder(after: templates))
                templates.append(saved)
            }
            return .saved(saved)
        } catch {
            let failure = Self.failure(error)
            switch failure {
            case .duplicate:
                // Someone else added it moments ago: fetch it so "Replace" has something to update.
                await load()
                return .duplicate(existing: existing(titled: draft.title, excluding: id))
            case .notFound:
                await load()
                return .failed(failure.errorDescription ?? "")
            case .sessionExpired:
                onSessionExpired()
                return .failed(failure.errorDescription ?? "")
            default:
                return .failed((failure.errorDescription ?? "") + " Your changes are still here.")
            }
        }
    }

    /// Removes it from the list straight away and puts it back if the delete fails.
    func delete(id: UUID) async {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let removed = templates.remove(at: index)
        listError = nil
        do {
            try await repository.delete(id: id)
        } catch {
            templates.insert(removed, at: min(index, templates.count))
            report(error, action: "delete that favourite")
        }
    }

    /// Applies a drag in the list straight away, then writes only the positions that changed.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        let before = templates
        let result = FavouriteRules.reordered(FavouriteRules.moving(templates, fromOffsets: source, toOffset: destination))
        templates = result.list
        guard !result.changes.isEmpty else { return }
        listError = nil
        do {
            try await repository.updateSortOrders(result.changes)
        } catch {
            templates = before
            report(error, action: "save the new order")
        }
    }

    func dismissListError() {
        listError = nil
    }

    private func report(_ error: any Error, action: String) {
        let failure = Self.failure(error)
        switch failure {
        case .cancelled: break
        case .sessionExpired: onSessionExpired()
        default: listError = "Couldn't \(action). \(failure.errorDescription ?? "")"
        }
    }

    private static func failure(_ error: any Error) -> DataServiceError {
        (error as? DataServiceError) ?? .server
    }
}
