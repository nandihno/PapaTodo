import SwiftUI

/// Says how current the chore on screen is (docs/phase-8-offline-plan.md): "Getting the
/// latest…" while Supabase is asked, a brief "Up to date" when that works, and a lasting
/// notice with a Refresh button when it doesn't.
struct FreshnessBannerView: View {
    let model: ChoreDetailModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.freshness {
            case .checking:
                banner {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Getting the latest…")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.freshness")
            case .upToDate:
                if model.confirmsUpToDate {
                    banner {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("detail.freshness")
                    }
                    .onAppear { AccessibilityNotification.Announcement("Up to date").post() }
                }
            case .unreachable(let savedAt):
                unreachable(savedAt: savedAt)
            }
        }
        .animation(reduceMotion ? nil : .default, value: model.freshness)
        .animation(reduceMotion ? nil : .default, value: model.confirmsUpToDate)
    }

    private func unreachable(savedAt: Date?) -> some View {
        banner {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let savedAt {
                        Text("Saved copy · updated \(savedAt, format: .relative(presentation: .named))")
                            .fontWeight(.semibold)
                    } else {
                        Text("Couldn't get the latest").fontWeight(.semibold)
                    }
                    if model.isReadOnly {
                        Text("Reconnect to make changes.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // On the text, not the banner: a container's identifier hides the Refresh button's.
                .accessibilityIdentifier("detail.freshness")
                Button("Refresh") {
                    Task { await model.load() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityHint("Tries to get the latest version of this chore.")
                .accessibilityIdentifier("detail.refresh")
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .transition(.opacity)
    }
}
