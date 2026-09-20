import SwiftUI

/// Full-screen photo browsing: swipe between a chore's photos, pinch to zoom, double-tap to
/// reset. Photos are decorative in the list; here each one is labelled "Photo n of m".
struct PhotoViewerView: View {
    let attachments: [ChoreAttachment]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { position, attachment in
                    ZoomablePhoto(url: attachment.publicURL)
                        .tag(position)
                        // One element per page, so VoiceOver reads "Photo 2 of 4" whether or not the image has loaded.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Photo \(position + 1) of \(attachments.count)")
                        .accessibilityAddTraits(.isImage)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding()
            .accessibilityLabel("Close full screen photo")
            .accessibilityIdentifier("photo.close")
        }
        .statusBarHidden()
    }
}

private struct ZoomablePhoto: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, min(baseScale * $0.magnification, 5)) }
                            .onEnded { _ in baseScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        // Reduce Motion: reset without the zoom animation.
                        withAnimation(reduceMotion ? nil : .default) { scale = 1; baseScale = 1 }
                    }
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("Couldn't load this photo")
                }
                .foregroundStyle(.white)
            default:
                ProgressView().tint(.white)
            }
        }
    }
}
