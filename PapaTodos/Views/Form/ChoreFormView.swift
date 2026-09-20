import SwiftUI

extension ChoreStatus {
    var displayName: String { ChoreSearch.statusLabel(for: self) }
}

/// The create / edit chore form. Presented as a sheet from Home.
struct ChoreFormView: View {
    @State private var model: ChoreFormModel
    /// Called once after a successful save or delete, with an optional caveat to show and
    /// whether the chore was deleted.
    let onFinished: (String?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingDelete = false
    /// The stored description, kept for the read-only view of a protected one.
    private let storedDescription: String?

    init(model: ChoreFormModel, storedDescription: String?, onFinished: @escaping (String?, Bool) -> Void) {
        _model = State(initialValue: model)
        self.storedDescription = storedDescription
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("form.error")
                    }
                }

                titleSection
                descriptionSection
                assigneeAndStatusSection
                dueSection
                PhotosSectionView(model: model)

                if model.isEditing {
                    Section {
                        Button("Delete Chore", role: .destructive) { isConfirmingDelete = true }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("form.delete")
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Chore" : "New Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.isDirty { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("form.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.phase == .saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await model.save() } }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("form.save")
                    }
                }
            }
            .interactiveDismissDisabled(model.isDirty || model.isBusy)
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog("Delete this chore?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Chore", role: .destructive) { Task { await model.delete() } }
                    .accessibilityIdentifier("form.confirmDelete")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes its comments and photos and can't be undone.")
            }
            .task { await model.loadPeople() }
            .task { await seedPhotoForUITests() }
            .onChange(of: model.didFinish) { _, finished in
                guard finished else { return }
                onFinished(model.notice, model.wasDeleted)
                dismiss()
            }
        }
    }

    // MARK: sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $model.title)
                .submitLabel(.next)
                .onChange(of: model.title) { model.clearTitleError() }
                .accessibilityIdentifier("form.title")
            if let error = model.titleError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("form.titleError")
            }
        } header: {
            Text("Title")
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            if model.isDescriptionProtected {
                ProtectedDescriptionView(stored: storedDescription) {
                    model.beginEditingProtectedDescription()
                }
            } else {
                DescriptionEditorView(text: $model.descriptionText)
            }
        } header: {
            Text("Description")
        }
    }

    private var assigneeAndStatusSection: some View {
        Section {
            Picker("Assigned to", selection: $model.assignedTo) {
                Text("Unassigned").tag(UUID?.none)
                ForEach(assigneeChoices) { person in
                    Text(person.fullName ?? "Family member").tag(UUID?.some(person.id))
                }
            }
            .accessibilityIdentifier("form.assignee")

            Picker("Status", selection: $model.status) {
                ForEach(ChoreStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .accessibilityIdentifier("form.status")
        }
    }

    /// The people list, plus the current assignee if they aren't in it, so the picker never
    /// shows a blank selection.
    private var assigneeChoices: [ProfileSummary] {
        var choices = model.people
        if let id = model.assignedTo, !choices.contains(where: { $0.id == id }) {
            choices.append(ProfileSummary(id: id, fullName: nil, avatarURL: nil))
        }
        return choices
    }

    private var dueSection: some View {
        Section {
            Toggle("Due date", isOn: $model.due.hasDueDate)
                .accessibilityIdentifier("form.hasDueDate")
            if model.due.hasDueDate {
                DatePicker("Date", selection: $model.due.day, displayedComponents: .date)
                    .accessibilityIdentifier("form.dueDate")
                Toggle("Due time", isOn: $model.due.hasDueTime)
                    .accessibilityIdentifier("form.hasDueTime")
                if model.due.hasDueTime {
                    DatePicker("Time", selection: $model.due.time, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("form.dueTime")
                }
            }
        } header: {
            Text("Due")
        } footer: {
            Text(model.due.hasDueDate ? "Leave the time off for a chore that's due some time that day." : "")
        }
    }

    /// UI tests can't drive the system photo picker, so `-UITestSeedPhoto` adds a generated
    /// image to a new form (only with `-UITestFixtures`).
    private func seedPhotoForUITests() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestFixtures"), arguments.contains("-UITestSeedPhoto"), !model.isEditing else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80))
        let data = renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        await model.addPhotos([(data, "seeded.png")])
    }
}
