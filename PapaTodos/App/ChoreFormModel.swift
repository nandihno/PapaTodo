import Foundation
import Observation

/// State and rules behind the create/edit chore form.
///
/// Safety rules, all covered by tests:
/// - An edit sends only the fields the user changed, so an untouched due date (and its
///   date-only sentinel) or an untouched description is never rewritten.
/// - A description the editor can't represent (lists, tables, emphasis...) stays exactly as
///   stored unless the user explicitly chooses to edit it as simplified text.
/// - Only one save or delete runs at a time, and the draft survives any failure.
@Observable
@MainActor
final class ChoreFormModel {
    enum Mode {
        case create
        case edit(Chore)
    }

    enum Phase: Equatable {
        case editing, saving, deleting
    }

    let mode: Mode
    private let original: Chore?
    private let currentUserID: UUID?
    private let saveService: ChoreSaveService
    private let deleteService: ChoreDeleteService
    private let profiles: any ProfileRepository
    private let notifier: (any NotificationDispatching)?
    private let onSessionExpired: @MainActor () -> Void

    // MARK: form fields

    var title = ""
    private(set) var titleError: String?
    var descriptionText = AttributedString()
    /// The stored description has structure the editor can't hold; it is shown read-only.
    private(set) var isDescriptionProtected = false
    var assignedTo: UUID?
    var status: ChoreStatus = .pending
    var due: DueDateForm.Fields
    private(set) var people: [ProfileSummary] = []

    // MARK: photos

    private(set) var existingAttachments: [ChoreAttachment] = []
    private(set) var removedAttachments: [ChoreAttachment] = []
    private(set) var pendingPhotos: [PhotoUpload] = []
    private(set) var photoMessage: String?

    // MARK: outcome

    private(set) var phase: Phase = .editing
    private(set) var errorMessage: String?
    /// A non-blocking note after a successful save/delete (for example, files left in storage).
    private(set) var notice: String?
    private(set) var didFinish = false
    /// The finish was a delete, not a save.
    private(set) var wasDeleted = false

    // MARK: baselines for change detection

    private let initialTitle: String
    private let initialDescription: AttributedString
    private let initialDue: DueDateForm.Fields
    private let initialAssignedTo: UUID?
    private let initialStatus: ChoreStatus
    private var descriptionWasSimplified = false

    init(
        mode: Mode,
        saveService: ChoreSaveService,
        deleteService: ChoreDeleteService,
        profiles: any ProfileRepository,
        currentUserID: UUID?,
        notifier: (any NotificationDispatching)? = nil,
        now: Date = Date(),
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.mode = mode
        self.saveService = saveService
        self.deleteService = deleteService
        self.profiles = profiles
        self.currentUserID = currentUserID
        self.notifier = notifier
        self.onSessionExpired = onSessionExpired

        let initialFields: DueDateForm.Fields
        switch mode {
        case .create:
            original = nil
            initialFields = DueDateForm.fields(for: nil, now: now)
            initialTitle = ""
            initialDescription = AttributedString()
            initialAssignedTo = nil
            initialStatus = .pending
        case .edit(let chore):
            original = chore
            title = chore.title
            let loaded = DescriptionEditing.load(chore.description)
            descriptionText = loaded.text
            isDescriptionProtected = loaded.isProtected
            assignedTo = chore.assignedTo
            status = chore.status
            initialFields = DueDateForm.fields(for: chore.dueDate, now: now)
            existingAttachments = ChoreAttachments.all(for: chore)
            initialTitle = chore.title
            initialDescription = loaded.text
            initialAssignedTo = chore.assignedTo
            initialStatus = chore.status
        }
        due = initialFields
        initialDue = initialFields
    }

    var isEditing: Bool { original != nil }

    /// Only the person who created a chore may delete it (the database enforces this too).
    var canDelete: Bool {
        guard let original, let currentUserID else { return false }
        return original.createdBy == currentUserID
    }
    var isBusy: Bool { phase != .editing }

    /// Whether leaving now would lose something.
    var isDirty: Bool {
        title != initialTitle
            || assignedTo != initialAssignedTo
            || status != initialStatus
            || due != initialDue
            || descriptionChanged
            || !pendingPhotos.isEmpty
            || !removedAttachments.isEmpty
    }

    private var descriptionChanged: Bool {
        !isDescriptionProtected && (descriptionWasSimplified || descriptionText != initialDescription)
    }

    // MARK: loading

    func loadPeople() async {
        if let fetched = try? await profiles.fetchProfiles() { people = fetched }
    }

    // MARK: description

    /// The explicit choice to edit a protected description: it becomes plain text with
    /// links, and lists, tables and emphasis are flattened.
    func beginEditingProtectedDescription() {
        guard isDescriptionProtected, let original else { return }
        descriptionText = DescriptionEditing.simplifiedText(from: original.description)
        isDescriptionProtected = false
        descriptionWasSimplified = true
    }

    // MARK: photos

    /// Prepares picked or pasted images. If any item isn't an image, none are added.
    func addPhotos(_ inputs: [(data: Data, name: String?)], source: PhotoSource = .library) async {
        var prepared: [PhotoUpload] = []
        for input in inputs {
            let name = input.name
            let data = input.data
            do {
                prepared.append(try await Task.detached(priority: .userInitiated) {
                    try ImageProcessing.prepare(data: data, suggestedName: name)
                }.value)
            } catch {
                photoMessage = "Choose or paste image files only."
                return
            }
        }
        guard !prepared.isEmpty else { return }
        pendingPhotos += prepared
        errorMessage = nil
        switch source {
        case .pasteboard: photoMessage = "Photo pasted from the clipboard."
        case .library: photoMessage = prepared.count > 1 ? "\(prepared.count) photos selected." : nil
        }
    }

    enum PhotoSource { case library, pasteboard }

    func noteNoImageOnPasteboard() {
        photoMessage = "No image was found on the clipboard. Try copying the photo again."
    }

    func removePendingPhoto(id: UUID) {
        pendingPhotos.removeAll { $0.id == id }
    }

    func removeExistingAttachment(_ attachment: ChoreAttachment) {
        guard existingAttachments.contains(where: { $0.id == attachment.id }) else { return }
        existingAttachments.removeAll { $0.id == attachment.id }
        removedAttachments.append(attachment)
    }

    // MARK: save

    func save() async {
        guard phase == .editing else { return }   // ignore a second tap while one is in flight
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            titleError = "Title is required."
            return
        }
        titleError = nil
        errorMessage = nil
        phase = .saving

        switch await saveService.save(makeRequest(title: trimmedTitle)) {
        case .success(let success):
            notice = Self.notice(for: success.warnings)
            // Fire and forget: a notification problem must never turn a saved chore into an error.
            if let event = success.notification, let notifier {
                let choreID = success.chore.id
                Task { await notifier.notify(event, choreID: choreID) }
            }
            didFinish = true
        case .failure(let failure):
            if failure.error == .sessionExpired {
                onSessionExpired()
            } else {
                errorMessage = Self.message(for: failure)
            }
        }
        phase = .editing
    }

    func clearTitleError() {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { titleError = nil }
    }

    private func makeRequest(title: String) -> ChoreSaveService.Request {
        let dueDate = DueDateForm.timestamp(for: due)
        guard let original else {
            return .init(
                kind: .create(ChoreDraft(
                    title: title, description: DescriptionEditing.storageValue(for: descriptionText),
                    assignedTo: assignedTo, status: status, dueDate: dueDate
                )),
                newPhotos: pendingPhotos
            )
        }

        var patch = ChorePatch()
        if title != original.title { patch.title = title }
        if descriptionChanged { patch.description = .some(DescriptionEditing.storageValue(for: descriptionText)) }
        if assignedTo != original.assignedTo { patch.assignedTo = .some(assignedTo) }
        if status != original.status { patch.status = status }
        if due != initialDue { patch.dueDate = .some(dueDate) }
        return .init(
            kind: .edit(original: original, patch: patch),
            keep: existingAttachments, remove: removedAttachments, newPhotos: pendingPhotos
        )
    }

    // MARK: delete

    func delete() async {
        guard let original, phase == .editing else { return }
        guard canDelete else {
            errorMessage = DataServiceError.notCreator.errorDescription
            return
        }
        errorMessage = nil
        phase = .deleting
        switch await deleteService.delete(original) {
        case .success(let outcome):
            if !outcome.leftoverPaths.isEmpty {
                notice = "Chore deleted. \(outcome.leftoverPaths.count == 1 ? "1 photo file is" : "\(outcome.leftoverPaths.count) photo files are") still in storage and can't be removed yet."
            }
            wasDeleted = true
            didFinish = true
        case .failure(let error):
            if error == .sessionExpired {
                onSessionExpired()
            } else {
                errorMessage = error.errorDescription
            }
        }
        phase = .editing
    }

    // MARK: messages

    private static func message(for failure: ChoreSaveService.Failure) -> String {
        var message = failure.error.errorDescription ?? DataServiceError.server.errorDescription ?? ""
        message += " Your changes are still here."
        if !failure.orphanedPaths.isEmpty {
            message += " Some uploaded photo files couldn't be cleaned up."
        }
        if failure.orphanedChoreID != nil {
            message += " A partly saved chore may appear in the list."
        }
        return message
    }

    private static func notice(for warnings: [ChoreSaveService.Warning]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.map { warning -> String in
            switch warning {
            case .removedPhotosNotDeleted(let error):
                "Saved, but the removed photos could not be deleted. \(error.errorDescription ?? "")"
            case .storageCleanupIncomplete(let paths):
                "Saved. \(paths.count == 1 ? "1 removed photo file is" : "\(paths.count) removed photo files are") still in storage and can't be deleted yet."
            }
        }.joined(separator: " ")
    }
}
