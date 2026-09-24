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
    @Environment(FavouritesStore.self) private var favourites
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingDelete = false
    /// A favourite swap or clear waiting for confirmation, because it would replace changes.
    @State private var pendingFavourite: PendingFavourite?

    private enum PendingFavourite {
        case use(ChoreTemplate)
        case clear(ChoreTemplate)

        var template: ChoreTemplate {
            switch self {
            case .use(let template), .clear(let template): template
            }
        }
    }

    init(model: ChoreFormModel, onFinished: @escaping (String?, Bool) -> Void) {
        _model = State(initialValue: model)
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

                if showsFavouriteChips {
                    favouriteChipsSection
                }
                titleSection
                descriptionSection
                assigneeAndStatusSection
                dueSection
                PhotosSectionView(model: model)

                if model.canDelete {
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
            .confirmationDialog(
                pendingFavouriteTitle,
                isPresented: Binding(get: { pendingFavourite != nil }, set: { if !$0 { pendingFavourite = nil } }),
                titleVisibility: .visible,
                presenting: pendingFavourite
            ) { pending in
                switch pending {
                case .use(let template):
                    Button("Use “\(template.title)”") { model.apply(template) }
                        .accessibilityIdentifier("form.confirmFavourite")
                case .clear:
                    Button("Clear", role: .destructive) { model.clearFavourite() }
                        .accessibilityIdentifier("form.confirmFavourite")
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                switch pending {
                case .use:
                    Text("The title, description and assignee are replaced. The due date, status and photos stay as they are.")
                case .clear:
                    Text("The title, description and assignee are cleared. The due date, status and photos stay as they are.")
                }
            }
            .task { await model.loadPeople() }
            .task { if !model.isEditing { await favourites.load() } }
            .task { await seedPhotoForUITests() }
            .onChange(of: model.didFinish) { _, finished in
                guard finished else { return }
                onFinished(model.notice, model.wasDeleted)
                dismiss()
            }
        }
    }

    // MARK: favourites

    /// A new chore always shows the favourites, so you can switch between them at any point.
    private var showsFavouriteChips: Bool {
        !model.isEditing && !favourites.templates.isEmpty
    }

    /// Suggestions only while typing a title from scratch; once a favourite is picked the chips
    /// already show it and the others.
    private var titleSuggestions: [ChoreTemplate] {
        guard !model.isEditing, model.appliedFavouriteID == nil else { return [] }
        return favourites.suggestions(for: model.title)
    }

    private var pendingFavouriteTitle: String {
        switch pendingFavourite {
        case .use(let template): "Replace your changes with “\(template.title)”?"
        case .clear: "Clear the favourite and your changes?"
        case nil: ""
        }
    }

    private var favouriteChipsSection: some View {
        Section {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favourites.templates) { template in
                            favouriteChip(template)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Opened from a favourite further along the row: bring it into view.
                .onAppear {
                    if let id = model.appliedFavouriteID { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text("Start from a favourite")
        } footer: {
            if model.appliedFavouriteID != nil {
                Text("Tap another favourite to switch, or tap this one again to clear it.")
            }
        }
    }

    @ViewBuilder
    private func favouriteChip(_ template: ChoreTemplate) -> some View {
        let isSelected = model.appliedFavouriteID == template.id
        let chip = Button {
            choose(template)
        } label: {
            Label(template.title, systemImage: isSelected ? "checkmark" : "star")
                .lineLimit(1)
                .frame(minHeight: 32)
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Favourite \(template.title)")
        .accessibilityHint(isSelected ? "Clears it from this chore." : "Fills in the title, description and assignee.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("form.favourite")
        .id(template.id)

        if isSelected {
            chip.buttonStyle(.borderedProminent)
        } else {
            chip.buttonStyle(.bordered)
        }
    }

    /// Picks, swaps or clears a favourite, asking first only if it would replace something the
    /// user wrote.
    private func choose(_ template: ChoreTemplate) {
        let isSelected = model.appliedFavouriteID == template.id
        if model.favouriteChangeNeedsConfirmation {
            pendingFavourite = isSelected ? .clear(template) : .use(template)
        } else if isSelected {
            model.clearFavourite()
        } else {
            model.apply(template)
        }
    }

    // MARK: sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $model.title)
                .submitLabel(.next)
                .onChange(of: model.title) { model.clearTitleError() }
                .accessibilityIdentifier("form.title")
            ForEach(titleSuggestions) { template in
                Button {
                    choose(template)
                } label: {
                    Label(template.title, systemImage: "star")
                }
                .accessibilityLabel("Use favourite \(template.title)")
                .accessibilityIdentifier("form.suggestion")
            }
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
                ProtectedDescriptionView(stored: model.protectedDescription) {
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
