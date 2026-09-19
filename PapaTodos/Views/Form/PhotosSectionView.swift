import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The photo controls for the chore form: existing and pending photos with remove buttons,
/// a multi-select photo picker, and paste from the clipboard.
struct PhotosSectionView: View {
    let model: ChoreFormModel

    @State private var pickerItems: [PhotosPickerItem] = []
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 96

    var body: some View {
        Section {
            if !model.existingAttachments.isEmpty || !model.pendingPhotos.isEmpty {
                // A horizontal row of fixed-size tiles: a lazy grid inside a Form row gets no
                // usable width and collapses.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.existingAttachments.enumerated()), id: \.element.id) { index, attachment in
                            PhotoTile(size: tileSize, label: "Photo \(index + 1)", onRemove: { model.removeExistingAttachment(attachment) }) {
                                AsyncImage(url: attachment.publicURL) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "photo").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        ForEach(Array(model.pendingPhotos.enumerated()), id: \.element.id) { index, photo in
                            PhotoTile(size: tileSize, label: "New photo \(index + 1)", onRemove: { model.removePendingPhoto(id: photo.id) }) {
                                if let image = UIImage(data: photo.data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
            }
            .accessibilityIdentifier("form.choosePhotos")

            HStack {
                Text("Paste a copied photo")
                Spacer()
                PasteButton(supportedContentTypes: [.image]) { providers in
                    Task { await paste(providers) }
                }
                .accessibilityIdentifier("form.pastePhoto")
            }

            if let message = model.photoMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("form.photoMessage")
            }
        } header: {
            Text("Photos")
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [(data: Data, name: String?)] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append((data, nil))
                    }
                }
                pickerItems = []
                await model.addPhotos(loaded)
            }
        }
    }

    private func paste(_ providers: [NSItemProvider]) async {
        var loaded: [(data: Data, name: String?)] = []
        for provider in providers {
            if let data = await Self.imageData(from: provider) {
                loaded.append((data, "pasted-photo"))
            }
        }
        if loaded.isEmpty {
            model.noteNoImageOnPasteboard()
        } else {
            await model.addPhotos(loaded, source: .pasteboard)
        }
    }

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// A square photo with a remove button that meets the 44pt minimum target.
private struct PhotoTile<Content: View>: View {
    let size: CGFloat
    let label: String
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(label.lowercased())")
                .accessibilityIdentifier("form.removePhoto")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
