import SwiftUI

/// The comment list and the pinned "Add a comment" bar.
struct CommentsSectionView: View {
    let model: ChoreDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            if let error = model.commentsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("detail.commentsError")
            }
            if model.isReconnecting {
                Label("Reconnecting to live comments…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.reconnecting")
            }

            if model.comments.isEmpty {
                Text("No comments yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.noComments")
            } else {
                ForEach(model.comments) { comment in
                    CommentRow(comment: comment, author: model.author(of: comment))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommentRow: View {
    let comment: ChoreComment
    let author: ProfileSummary?

    var body: some View {
        let name = author?.fullName ?? "Unknown"
        HStack(alignment: .top, spacing: 12) {
            ProfileAvatarView(name: name, url: author?.avatarURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name).font(.subheadline.weight(.semibold))
                    Text(CommentTime.label(for: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(comment.body)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.comment")
    }
}

/// The text field and Send button, pinned to the bottom of the detail screen.
struct CommentBarView: View {
    @Bindable var model: ChoreDetailModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Add a comment…", text: $model.commentDraft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.separator))
                .disabled(model.chore == nil || model.isSendingComment)
                .accessibilityLabel("Add a comment")
                .accessibilityIdentifier("detail.commentField")

            Button {
                Task { await model.sendComment() }
            } label: {
                if model.isSendingComment {
                    ProgressView().frame(minWidth: 44, minHeight: 44)
                } else {
                    Text("Send").frame(minWidth: 44, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSendComment)
            .accessibilityIdentifier("detail.sendComment")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
