import SwiftUI

/// The read-only chore view: photos, status, description, people, due date, Mark as Done,
/// calendar buttons and comments. Editing lives behind the Edit button, as on the web.
struct ChoreDetailView: View {
    @State private var model: ChoreDetailModel
    let formFactory: ChoreFormFactory
    /// Called after an edit or delete so the list can refresh and show any caveat (for example,
    /// photo files that could not be removed from storage).
    let onChanged: (_ notice: String?, _ deleted: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var viewerIndex: ViewerRoute?
    @State private var isEditing = false

    private struct ViewerRoute: Identifiable {
        let index: Int
        var id: Int { index }
    }

    init(model: ChoreDetailModel, formFactory: ChoreFormFactory, onChanged: @escaping (String?, Bool) -> Void) {
        _model = State(initialValue: model)
        self.formFactory = formFactory
        self.onChanged = onChanged
    }

    var body: some View {
        content
            .navigationTitle(model.chore?.title ?? "Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Chore", systemImage: "pencil")
                    }
                    .disabled(model.chore == nil)
                    .accessibilityIdentifier("detail.edit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                CommentBarView(model: model)
            }
            .task { await model.load() }
            // Runs the live subscription for exactly as long as this screen is showing.
            .task { await model.listen() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.reloadComments() } }
            }
            .fullScreenCover(item: $viewerIndex) { route in
                PhotoViewerView(attachments: attachments, index: route.index)
            }
            .sheet(isPresented: $isEditing) { editForm }
            .sheet(isPresented: calendarSheetBinding) {
                if case .presenting(let draft) = model.calendar {
                    EventEditView(draft: draft) { model.finishCalendarSave($0) }
                        .ignoresSafeArea()
                }
            }
    }

    private var attachments: [ChoreAttachment] {
        model.chore.map(ChoreAttachments.all(for:)) ?? []
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading chore…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notFound:
            ContentUnavailableView("Chore not found", systemImage: "questionmark.folder",
                                   description: Text("It may have been deleted."))
        case .failed(let error):
            ContentUnavailableView {
                Label("Could not load chore", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "")
            } actions: {
                Button("Try Again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if let chore = model.chore { loaded(chore) }
        }
    }

    private func loaded(_ chore: Chore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                card(chore)
                CommentsSectionView(model: model)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await model.load() }
        .accessibilityIdentifier("detail.scroll")
    }

    // MARK: card

    private func card(_ chore: Chore) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            photos

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chore.title)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    statusButton(chore)
                }

                description(chore)
                Divider()
                people(chore)
                Divider()
                dueDate(chore)

                if let error = model.statusError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("detail.statusError")
                }

                if chore.status != .done {
                    Button {
                        Task { await model.markDone() }
                    } label: {
                        Text("Mark as Done").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isUpdatingStatus)
                    .accessibilityIdentifier("detail.markDone")
                }

                calendarActions(chore)
            }
            .padding()
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var photos: some View {
        if let first = attachments.first {
            VStack(spacing: 0) {
                Button {
                    viewerIndex = ViewerRoute(index: 0)
                } label: {
                    AsyncImage(url: first.publicURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.secondary.opacity(0.15).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View chore photo full screen")
                .accessibilityIdentifier("detail.photo")

                if attachments.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(attachments.enumerated()), id: \.element.id) { position, attachment in
                                Button {
                                    viewerIndex = ViewerRoute(index: position)
                                } label: {
                                    AsyncImage(url: attachment.publicURL) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.secondary.opacity(0.15)
                                        }
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View attachment \(position + 1)")
                                .accessibilityIdentifier("detail.thumb")
                            }
                        }
                        .padding(8)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Chore attachments")
                }
            }
        }
    }

    private func statusButton(_ chore: Chore) -> some View {
        Button {
            Task { await model.advanceStatus() }
        } label: {
            Label(ChoreSearch.statusLabel(for: chore.status), systemImage: statusSymbol(chore.status))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isUpdatingStatus)
        .accessibilityLabel("Status: \(ChoreSearch.statusLabel(for: chore.status))")
        .accessibilityHint("Changes the status to \(ChoreSearch.statusLabel(for: chore.status.next)).")
        .accessibilityIdentifier("detail.status")
    }

    private func statusSymbol(_ status: ChoreStatus) -> String {
        switch status {
        case .pending: "circle"
        case .inProgress: "clock.arrow.circlepath"
        case .done: "checkmark.circle.fill"
        }
    }

    @ViewBuilder
    private func description(_ chore: Chore) -> some View {
        if let text = DescriptionDisplay.attributed(from: chore.description) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.description")
        } else {
            Text("No description.").foregroundStyle(.secondary)
        }
    }

    private func people(_ chore: Chore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            person(title: "Assigned to", profile: chore.assignedProfile, fallback: "Unassigned")
            person(title: "Created by", profile: chore.createdProfile, fallback: "Unknown")
        }
    }

    private func person(title: String, profile: ProfileSummary?, fallback: String) -> some View {
        let name = profile?.fullName ?? fallback
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProfileAvatarView(name: name, url: profile?.avatarURL, size: 32)
                Text(name).font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dueDate(_ chore: Chore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DUE DATE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(ChoreDueLabel.detail(for: chore.dueDate)).font(.headline)
                .accessibilityIdentifier("detail.dueDate")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: calendar

    @ViewBuilder
    private func calendarActions(_ chore: Chore) -> some View {
        if chore.dueDate != nil {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { saveToCalendarButton(chore); googleCalendarButton(chore) }
                    VStack(spacing: 12) { saveToCalendarButton(chore); googleCalendarButton(chore) }
                }
                calendarMessage
            }
        }
    }

    private func saveToCalendarButton(_ chore: Chore) -> some View {
        Button {
            model.prepareCalendarSave()
        } label: {
            Text("Save to Calendar").frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("detail.saveToCalendar")
    }

    @ViewBuilder
    private func googleCalendarButton(_ chore: Chore) -> some View {
        if let url = GoogleCalendarURL.make(for: chore) {
            Button {
                openURL(url)
            } label: {
                Text("Google Calendar").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens Google Calendar in your browser with this chore filled in.")
            .accessibilityIdentifier("detail.googleCalendar")
        }
    }

    @ViewBuilder
    private var calendarMessage: some View {
        switch model.calendar {
        case .saved:
            calendarNote("Added to your calendar.", symbol: "checkmark.circle.fill", tint: .green)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                calendarNote("Calendar access is off for Papa Todos. Turn it on in Settings to save events.", symbol: "calendar.badge.exclamationmark", tint: .red)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("detail.openSettings")
            }
        case .restricted:
            calendarNote("Calendar access is restricted on this device.", symbol: "calendar.badge.exclamationmark", tint: .red)
        case .failed(let message):
            calendarNote(message, symbol: "exclamationmark.triangle.fill", tint: .red)
        case .idle, .presenting, .cancelled:
            EmptyView()
        }
    }

    private func calendarNote(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label { Text(text).font(.footnote) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            Spacer()
            Button("Dismiss") { model.dismissCalendarMessage() }.font(.footnote)
        }
        .accessibilityIdentifier("detail.calendarMessage")
    }

    private var calendarSheetBinding: Binding<Bool> {
        Binding(
            get: { if case .presenting = model.calendar { true } else { false } },
            set: { presented in
                if !presented, case .presenting = model.calendar { model.finishCalendarSave(.cancelled) }
            }
        )
    }

    // MARK: edit

    @ViewBuilder
    private var editForm: some View {
        if let chore = model.chore {
            ChoreFormView(
                model: formFactory.makeModel(mode: .edit(chore)), storedDescription: chore.description
            ) { notice, deleted in
                onChanged(notice, deleted)
                if deleted {
                    dismiss()
                } else {
                    Task { await model.load() }
                }
            }
        }
    }
}
