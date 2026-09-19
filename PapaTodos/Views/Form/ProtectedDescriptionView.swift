import SwiftUI

/// Shows a description the editor can't represent (lists, tables, emphasis...) exactly as
/// stored, and offers an explicit, confirmed way to convert it to editable text.
struct ProtectedDescriptionView: View {
    let stored: String?
    let onEditAsText: () -> Void

    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = DescriptionDisplay.attributed(from: stored) {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("form.protectedDescription")
            }
            Label(
                "This description has formatting (lists, tables or styling) that can't be edited here. It stays as it is unless you edit it as text.",
                systemImage: "lock"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button("Edit as Text…") { isConfirming = true }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("form.editAsText")
        }
        .confirmationDialog(
            "Edit as plain text?", isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button("Edit as Text", role: .destructive, action: onEditAsText)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Lists, tables and styling will be flattened to plain text. Links are kept.")
        }
    }
}
