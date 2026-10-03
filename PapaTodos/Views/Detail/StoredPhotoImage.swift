import SwiftUI
import UIKit

/// Like `AsyncImage`, but the bytes come from `load`, which serves the phone's saved copy of a
/// chore photo when there is one (docs/phase-8-offline-plan.md).
struct StoredPhotoImage<Content: View>: View {
    let url: URL
    let load: @MainActor (URL) async -> Data?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    private struct Unavailable: Error {}

    var body: some View {
        content(phase)
            .task(id: url) {
                phase = .empty
                let data = await load(url)
                // Decoding a full-size photo happens off the main thread.
                let image = await data.flatMap(UIImage.init(data:))?.byPreparingForDisplay()
                guard !Task.isCancelled else { return }
                phase = image.map { .success(Image(uiImage: $0)) } ?? .failure(Unavailable())
            }
    }
}
