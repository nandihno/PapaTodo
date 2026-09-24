import SwiftUI

/// Settings → Favourite Chores: the shared list, where anyone can add, edit, delete and reorder.
struct FavouritesListView: View {
    @Environment(FavouritesStore.self) private var store
    @State private var editor: EditorRoute?
    @State private var pendingDelete: ChoreTemplate?

    private enum EditorRoute: Identifiable {
        case add
        case edit(ChoreTemplate)
        var id: String {
            switch self {
            case .add: "add"
            case .edit(let template): template.id.uuidString
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Favourite Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .add
                    } label: {
                        Label("Add Favourite", systemImage: "plus")
                    }
                    .accessibilityIdentifier("favourites.add")
                }
                if store.templates.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .accessibilityIdentifier("favourites.reorder")
                    }
                }
            }
            .sheet(item: $editor) { route in
                switch route {
                case .add:
                    FavouriteEditorView(model: FavouriteEditorModel(mode: .create(nil), store: store))
                case .edit(let template):
                    FavouriteEditorView(model: FavouriteEditorModel(mode: .edit(template), store: store))
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDelete?.title ?? "")”?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { template in
                Button("Delete Favourite", role: .destructive) { Task { await store.delete(id: template.id) } }
                    .accessibilityIdentifier("favourites.confirmDelete")
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("It's removed for everyone. Chores already made from it aren't affected.")
            }
            .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading where store.templates.isEmpty:
            ProgressView("Loading favourites…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error) where store.templates.isEmpty:
            ContentUnavailableView {
                Label("Could not load favourites", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "")
            } actions: {
                Button("Try Again") { Task { await store.load() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if store.templates.isEmpty {
                ContentUnavailableView {
                    Label("No favourites yet", systemImage: "star")
                } description: {
                    Text("Save chores you make again and again, like a weekly shop. Tip: open any chore and choose Save as Favourite.")
                } actions: {
                    Button("Add Favourite") { editor = .add }
                        .buttonStyle(.borderedProminent)
                }
                .accessibilityIdentifier("favourites.empty")
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            if let error = store.listError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("favourites.error")
                    Button("Dismiss") { store.dismissListError() }
                }
            }
            Section {
                ForEach(store.templates) { template in
                    Button {
                        editor = .edit(template)
                    } label: {
                        row(template)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = template }
                    }
                    .accessibilityIdentifier("favourites.row")
                }
                .onMove { source, destination in
                    Task { await store.move(fromOffsets: source, toOffset: destination) }
                }
            } footer: {
                Text("Shared with everyone in the family. Use Edit to change the order; the first five show when you touch and hold + on the chore list.")
            }
        }
        .refreshable { await store.load() }
    }

    private func row(_ template: ChoreTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.title)
                .font(.body.weight(.medium))
            if let summary = Self.summary(of: template.description) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let name = store.name(of: template.assignedTo) {
                Label(name, systemImage: "person")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The description as one plain line, for the row preview.
    private static func summary(of description: String?) -> String? {
        let text = String(DescriptionEditing.simplifiedText(from: description).characters)
            .split(whereSeparator: \.isNewline)
            // Flattened lists start each item with a bullet or number; the separator replaces it.
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "•·-–"))) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}
