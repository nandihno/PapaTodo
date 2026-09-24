import Foundation
import Observation

/// State behind the add / edit favourite sheet.
///
/// Like the chore form, a description with structure the editor can't hold (a web-made list)
/// is kept exactly as stored unless the user explicitly chooses to edit it as text. A title
/// that clashes with another favourite offers to replace that one instead.
@Observable
@MainActor
final class FavouriteEditorModel {
    enum Mode {
        /// A new favourite, optionally pre-filled (for example, from an existing chore).
        case create(ChoreTemplateDraft?)
        case edit(ChoreTemplate)
    }

    let mode: Mode
    let store: FavouritesStore

    var title: String
    var descriptionText: AttributedString
    var assignedTo: UUID?
    private(set) var isDescriptionProtected: Bool
    private(set) var protectedDescription: String?

    private(set) var isSaving = false
    private(set) var titleError: String?
    private(set) var errorMessage: String?
    /// Another favourite already has this title; the sheet offers to replace it.
    private(set) var duplicate: ChoreTemplate?
    private(set) var didFinish = false

    private let initialTitle: String
    private let initialDescription: AttributedString
    private let initialAssignedTo: UUID?
    private var descriptionWasSimplified = false

    init(mode: Mode, store: FavouritesStore) {
        self.mode = mode
        self.store = store
        let draft: ChoreTemplateDraft? = switch mode {
        case .create(let draft): draft
        case .edit(let template): ChoreTemplateDraft(title: template.title, description: template.description, assignedTo: template.assignedTo)
        }
        let loaded = DescriptionEditing.load(draft?.description)
        title = draft?.title ?? ""
        descriptionText = loaded.text
        isDescriptionProtected = loaded.isProtected
        protectedDescription = loaded.isProtected ? draft?.description : nil
        assignedTo = draft?.assignedTo
        initialTitle = draft?.title ?? ""
        initialDescription = loaded.text
        initialAssignedTo = draft?.assignedTo
    }

    var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var editingID: UUID? {
        if case .edit(let template) = mode { template.id } else { nil }
    }

    var isDirty: Bool {
        title != initialTitle
            || assignedTo != initialAssignedTo
            || (!isDescriptionProtected && (descriptionWasSimplified || descriptionText != initialDescription))
    }

    func beginEditingProtectedDescription() {
        guard isDescriptionProtected else { return }
        descriptionText = DescriptionEditing.simplifiedText(from: protectedDescription)
        isDescriptionProtected = false
        protectedDescription = nil
        descriptionWasSimplified = true
    }

    func titleChanged() {
        duplicate = nil
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { titleError = nil }
    }

    var draft: ChoreTemplateDraft {
        ChoreTemplateDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: isDescriptionProtected ? protectedDescription : DescriptionEditing.storageValue(for: descriptionText),
            assignedTo: assignedTo
        )
    }

    func save() async {
        await save(id: editingID)
    }

    /// Overwrites the favourite that already has this title with what's in the sheet. When
    /// editing, the favourite being edited is deleted afterwards so the two become one.
    func replaceDuplicate() async {
        guard let duplicate else { return }
        let editedID = editingID
        await save(id: duplicate.id)
        if didFinish, let editedID { await store.delete(id: editedID) }
    }

    private func save(id: UUID?) async {
        guard !isSaving else { return }
        guard !draft.title.isEmpty else {
            titleError = "Title is required."
            return
        }
        titleError = nil
        errorMessage = nil
        duplicate = nil
        isSaving = true
        switch await store.save(draft, id: id) {
        case .saved:
            didFinish = true
        case .duplicate(let existing):
            if let existing {
                duplicate = existing
            } else {
                errorMessage = DataServiceError.duplicate.errorDescription
            }
        case .failed(let message):
            errorMessage = message
        }
        isSaving = false
    }
}
