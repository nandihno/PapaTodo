import SwiftUI

/// Adds or edits a favourite chore: title, description and default assignee.
struct FavouriteEditorView: View {
    @State private var model: FavouriteEditorModel
    /// Called once after a successful save, with the saved title.
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingReplace = false

    init(model: FavouriteEditorModel, onSaved: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("favourite.error")
                    }
                }
                if let duplicate = model.duplicate {
                    Section {
                        Label("A favourite called “\(duplicate.title)” already exists.", systemImage: "star.fill")
                            .accessibilityIdentifier("favourite.duplicate")
                        Button("Replace It With This One") { isConfirmingReplace = true }
                            .accessibilityIdentifier("favourite.replace")
                    } footer: {
                        Text("Or change the title to keep both.")
                    }
                }

                Section {
                    TextField("Title", text: $model.title)
                        .onChange(of: model.title) { model.titleChanged() }
                        .accessibilityIdentifier("favourite.title")
                    if let error = model.titleError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Title")
                }

                Section {
                    if model.isDescriptionProtected {
                        ProtectedDescriptionView(stored: model.protectedDescription) {
                            model.beginEditingProtectedDescription()
                        }
                    } else {
                        DescriptionEditorView(text: $model.descriptionText)
                    }
                } header: {
                    Text("Description")
                }

                Section {
                    Picker("Assign to", selection: $model.assignedTo) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(assigneeChoices) { person in
                            Text(person.fullName ?? "Family member").tag(UUID?.some(person.id))
                        }
                    }
                    .accessibilityIdentifier("favourite.assignee")
                } footer: {
                    Text("Using this favourite fills in the title, description and assignee. You can still change them, and add a due date and photos, before saving the chore.")
                }
            }
            .navigationTitle(model.isEditing ? "Edit Favourite" : "New Favourite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.isDirty { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("favourite.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await model.save() } }
                            .accessibilityIdentifier("favourite.save")
                    }
                }
            }
            .interactiveDismissDisabled(model.isDirty || model.isSaving)
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog("Replace the existing favourite?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
                Button("Replace", role: .destructive) { Task { await model.replaceDuplicate() } }
                    .accessibilityIdentifier("favourite.confirmReplace")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its description and assignee will be replaced for everyone.")
            }
            .task { if model.store.people.isEmpty { await model.store.loadPeople() } }
            .onChange(of: model.didFinish) { _, finished in
                guard finished else { return }
                onSaved(model.draft.title)
                dismiss()
            }
        }
    }

    /// The people list, plus the current assignee if they aren't in it, so the picker never
    /// shows a blank selection.
    private var assigneeChoices: [ProfileSummary] {
        var choices = model.store.people
        if let id = model.assignedTo, !choices.contains(where: { $0.id == id }) {
            choices.append(ProfileSummary(id: id, fullName: nil, avatarURL: nil))
        }
        return choices
    }
}
