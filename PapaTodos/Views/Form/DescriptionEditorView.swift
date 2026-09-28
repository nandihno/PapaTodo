import SwiftUI

/// The editing surface allows text and links only. Everything else the system text editor
/// could apply (bold, italic, underline, fonts, colors...) is filtered out, because only text,
/// links and bullet lines are stored. Bullets are plain "• " text (see `DescriptionBullets`).
private struct LinkOnlyScope: AttributeScope {
    let link: AttributeScopes.FoundationAttributes.LinkAttribute
}

private struct LinksOnlyFormatting: AttributedTextFormattingDefinition {
    typealias Scope = LinkOnlyScope
    var body: some AttributedTextFormattingDefinition<LinkOnlyScope> {}
}

/// A text editor with a Bullet List toggle and Add Link / Remove Link controls for the selected text.
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
                .onChange(of: text) { oldValue, newValue in
                    applyListRules(old: oldValue, new: newValue)
                }

            bulletListButton
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

    private var bulletListButton: some View {
        Button {
            toggleBullets()
        } label: {
            Label("Bullet List", systemImage: "list.bullet")
        }
        .accessibilityIdentifier("form.bulletList")
        .accessibilityHint("Turns the current or selected lines into bullet points, or back into plain lines.")
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

    /// The selection as character offsets (a caret is an empty range).
    private var selectedOffsets: Range<Int> {
        let end = text.characters.count
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            let offset = DescriptionBullets.offset(of: index, in: text) ?? end
            return offset..<offset
        case .ranges(let ranges):
            guard let first = ranges.ranges.first, let last = ranges.ranges.last,
                  let lower = DescriptionBullets.offset(of: first.lowerBound, in: text),
                  let upper = DescriptionBullets.offset(of: last.upperBound, in: text) else { return end..<end }
            return lower..<upper
        }
    }

    private func toggleBullets() {
        linkError = nil
        apply(DescriptionBullets.toggle(text, selection: selectedOffsets))
    }

    /// Return continues or ends a bullet list, and "- " starts one, as in Notes.
    private func applyListRules(old: AttributedString, new: AttributedString) {
        var caret: Int?
        if case .insertionPoint(let index) = selection.indices(in: new) {
            caret = DescriptionBullets.offset(of: index, in: new)
        }
        guard let result = DescriptionBullets.afterTyping(old: old, new: new, caret: caret) else { return }
        apply(result)
    }

    private func apply(_ result: DescriptionBullets.Result) {
        text = result.text
        let range = DescriptionBullets.range(result.selection, in: text)
        selection = range.isEmpty
            ? AttributedTextSelection(insertionPoint: range.lowerBound)
            : AttributedTextSelection(range: range)
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
