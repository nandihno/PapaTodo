import SwiftUI

/// The editing surface allows text and links only. Everything else the system text editor
/// could apply (bold, italic, underline, fonts, colors...) is filtered out, because only text
/// and links are stored.
private struct LinkOnlyScope: AttributeScope {
    let link: AttributeScopes.FoundationAttributes.LinkAttribute
}

private struct LinksOnlyFormatting: AttributedTextFormattingDefinition {
    typealias Scope = LinkOnlyScope
    var body: some AttributedTextFormattingDefinition<LinkOnlyScope> {}
}

/// A text editor with an Add Link / Remove Link control for the selected text.
struct DescriptionEditorView: View {
    @Binding var text: AttributedString

    @State private var selection = AttributedTextSelection()
    @State private var isAskingForLink = false
    @State private var linkAddress = ""
    @State private var linkError: String?

    /// The editor and its link controls are separate rows of the surrounding Form section:
    /// two bordered buttons squeezed into one row get truncated.
    var body: some View {
        Group {
            TextEditor(text: $text, selection: $selection)
                .attributedTextFormattingDefinition(LinksOnlyFormatting())
                .frame(minHeight: 120)
                .accessibilityLabel("Description")
                .accessibilityIdentifier("form.description")

            addLinkButton
            removeLinkButton

            if let linkError {
                Label(linkError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("form.linkError")
            }
        }
        .alert("Add Link", isPresented: $isAskingForLink) {
            TextField("https://example.com", text: $linkAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { applyLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a web address, email address, or phone number.")
        }
    }

    private var addLinkButton: some View {
        Button {
            linkAddress = ""
            isAskingForLink = true
        } label: {
            Label("Add Link…", systemImage: "link")
        }
        .accessibilityIdentifier("form.addLink")
        .accessibilityHint("Turns the selected text into a link, or inserts a link at the cursor.")
    }

    private var removeLinkButton: some View {
        Button {
            removeLink()
        } label: {
            Label("Remove Link", systemImage: "minus.circle")
        }
        .accessibilityIdentifier("form.removeLink")
        .accessibilityHint("Removes the link from the selected text.")
    }

    private var selectionIsEmpty: Bool {
        switch selection.indices(in: text) {
        case .insertionPoint: true
        case .ranges(let ranges): ranges.isEmpty
        }
    }

    private func applyLink() {
        linkError = nil
        guard let url = Self.url(from: linkAddress) else {
            linkError = "That isn't a link the app can open. Use a web address (https://…), email address, or phone number."
            return
        }
        if selectionIsEmpty {
            var inserted = AttributedString(Self.displayText(for: url))
            inserted.link = url
            text.replaceSelection(&selection, with: inserted)
        } else {
            text.transformAttributes(in: &selection) { $0.link = url }
        }
    }

    private func removeLink() {
        linkError = nil
        text.transformAttributes(in: &selection) { $0.link = nil }
    }

    /// Accepts what people actually type: "example.com", "https://…", an email address or a phone number.
    static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@"), !trimmed.contains("/"), !trimmed.contains(":") {
            return DescriptionHTML.safeURL("mailto:" + trimmed)
        }
        if trimmed.range(of: #"^\+?[0-9][0-9 ()\-]{5,}$"#, options: .regularExpression) != nil {
            return DescriptionHTML.safeURL("tel:" + trimmed.replacingOccurrences(of: " ", with: ""))
        }
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") || trimmed.hasPrefix("tel:") {
            return DescriptionHTML.safeURL(trimmed)
        }
        return DescriptionHTML.safeURL("https://" + trimmed)
    }

    static func displayText(for url: URL) -> String {
        switch url.scheme?.lowercased() {
        case "mailto": String(url.absoluteString.dropFirst("mailto:".count))
        case "tel": String(url.absoluteString.dropFirst("tel:".count))
        default: url.absoluteString
        }
    }
}
