import SwiftUI
import UIKit

/// One chore row on Home. Status and due state are always conveyed with an icon and
/// text as well as color, and the row reads as a single VoiceOver element.
struct ChoreCardView: View {
    let chore: Chore
    var now: Date = Date()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 64

    private var tone: DueTone { ChoreDueState.tone(for: chore, now: now) }
    private var dueLabel: String { ChoreDueLabel.label(for: chore, now: now) }
    private var assigneeName: String { chore.assignedProfile?.fullName ?? "Unassigned" }
    private var attachments: [ChoreAttachment] { ChoreAttachments.all(for: chore) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        layout {
            VStack(alignment: .leading, spacing: 8) {
                Text(chore.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusBadge
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { assignee; dueText }
                    VStack(alignment: .leading, spacing: 6) { assignee; dueText }
                }
            }
            if let primary = attachments.first {
                thumbnail(primary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("chore.card")
    }

    private var statusBadge: some View {
        Label(ChoreSearch.statusLabel(for: chore.status), systemImage: statusSymbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    private var assignee: some View {
        HStack(spacing: 6) {
            ProfileAvatarView(name: assigneeName, url: chore.assignedProfile?.avatarURL, size: 24)
            Text(assigneeName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The text stays in the primary color so it keeps full contrast; the icon and
    /// weight carry the overdue/today emphasis (never color alone).
    private var dueText: some View {
        Label {
            Text(dueLabel)
                .font(.subheadline.weight(tone == .overdue || tone == .today ? .semibold : .regular))
                .foregroundStyle(tone == .upcoming || tone == .done ? .secondary : .primary)
        } icon: {
            Image(systemName: dueSymbol).foregroundStyle(dueIconColor)
        }
    }

    private func thumbnail(_ attachment: ChoreAttachment) -> some View {
        AsyncImage(url: attachment.publicURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if attachments.count > 1 {
                Text("\(attachments.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
    }

    private var statusSymbol: String {
        switch chore.status {
        case .pending: "circle"
        case .inProgress: "clock.arrow.circlepath"
        case .done: "checkmark.circle.fill"
        }
    }

    private var dueSymbol: String {
        switch tone {
        case .overdue: "exclamationmark.triangle.fill"
        case .today: "sun.max.fill"
        case .upcoming: "calendar"
        case .done: "checkmark.circle"
        }
    }

    private var dueIconColor: Color {
        switch tone {
        case .overdue: .red
        case .today: Color(uiColor: todayIconUIColor())
        case .upcoming, .done: .secondary
        }
    }

    private var accessibilityDescription: String {
        var parts = [
            chore.title,
            "Status: \(ChoreSearch.statusLabel(for: chore.status))",
            "Assigned to \(assigneeName)",
            "Due: \(dueLabel)",
        ]
        if attachments.count > 1 {
            parts.append("\(attachments.count) attachments")
        } else if attachments.count == 1 {
            parts.append("1 attachment")
        }
        return parts.joined(separator: ". ")
    }
}

/// A darker orange in light mode so the "today" icon keeps 3:1 contrast on white.
/// `nonisolated` for the same reason as `personUIColor` (UIKit resolves it off-main).
private nonisolated func todayIconUIColor() -> UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 1)
            : UIColor(red: 0.78, green: 0.36, blue: 0.0, alpha: 1)
    }
}
