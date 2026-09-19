import Foundation

/// Converts between a stored description and what the native editor can hold: plain text
/// with links. Everything else the web sanitizer allows (lists, headings, tables, emphasis,
/// quotes, code) is rendered for reading but *protected* from silent loss: the editor only
/// touches such a description if the user explicitly chooses to simplify it.
nonisolated enum DescriptionEditing {
    struct Loaded: Equatable {
        var text: AttributedString
        /// The stored description has structure the editor can't represent.
        var isProtected: Bool
    }

    /// Tags a links-only editor can round-trip without losing anything.
    private static let representableTags: Set<String> = ["a", "br", "div", "p", "span"]

    static func load(_ stored: String?) -> Loaded {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Loaded(text: AttributedString(), isProtected: false)
        }
        guard DescriptionHTML.looksLikeHTML(stored) else {
            return Loaded(text: AttributedString(stored), isProtected: false)
        }
        let nodes = DescriptionHTML.sanitizedNodes(stored)
        let flattened = DescriptionFlattener.flatten(nodes, styled: false)
        return Loaded(text: flattened, isProtected: !isRepresentable(nodes))
    }

    /// The description as editable text with its structure flattened (used for the explicit
    /// "Edit as text" choice on a protected description).
    static func simplifiedText(from stored: String?) -> AttributedString {
        load(stored).text
    }

    private static func isRepresentable(_ nodes: [DescriptionHTML.Node]) -> Bool {
        nodes.allSatisfy { node in
            switch node {
            case .text: true
            case .element(let element):
                representableTags.contains(element.tag) && isRepresentable(element.children)
            }
        }
    }

    // MARK: storing

    private enum Segment {
        case text(String, URL?)
        case newline
    }

    /// The value to store, or nil for an empty description. Text with no links is stored as
    /// plain text, exactly as the web does; text with links is stored as sanitized HTML
    /// (`<p>`, `<br>`, `<a href>`). Plain text that the web would mistake for HTML (it
    /// contains something like `<b>`) is stored as escaped HTML so it displays literally.
    static func storageValue(for text: AttributedString) -> String? {
        let segments = trimmed(segments(of: text))
        guard !segments.isEmpty else { return nil }

        let hasLinks = segments.contains { if case .text(_, let url) = $0 { url != nil } else { false } }
        let plain = segments.map { segment -> String in
            switch segment {
            case .text(let string, _): string
            case .newline: "\n"
            }
        }.joined()

        if !hasLinks && !DescriptionHTML.looksLikeHTML(plain) {
            return plain
        }
        return html(from: segments)
    }

    private static func segments(of text: AttributedString) -> [Segment] {
        var result: [Segment] = []
        for run in text.runs {
            let url = run.link.flatMap { DescriptionHTML.safeURL($0.absoluteString) }
            var buffer = ""
            for character in text[run.range].characters {
                if character.isNewline {
                    if !buffer.isEmpty { result.append(.text(buffer, url)); buffer = "" }
                    result.append(.newline)
                } else {
                    buffer.append(character)
                }
            }
            if !buffer.isEmpty { result.append(.text(buffer, url)) }
        }
        return result
    }

    /// Drops leading/trailing newlines and edge whitespace, and returns [] if nothing visible remains.
    private static func trimmed(_ segments: [Segment]) -> [Segment] {
        var items = segments
        while case .newline? = items.first { items.removeFirst() }
        while case .newline? = items.last { items.removeLast() }
        if case .text(let string, let url)? = items.first {
            items[0] = .text(String(string.drop(while: { $0.isWhitespace })), url)
        }
        if case .text(let string, let url)? = items.last {
            var value = string
            while let last = value.last, last.isWhitespace { value.removeLast() }
            items[items.count - 1] = .text(value, url)
        }
        let hasVisibleText = items.contains { if case .text(let string, _) = $0 { !string.isEmpty } else { false } }
        return hasVisibleText ? items : []
    }

    private static func html(from segments: [Segment]) -> String {
        var paragraphs: [[Segment]] = [[]]
        var newlineRun = 0
        for segment in segments {
            switch segment {
            case .newline:
                newlineRun += 1
            case .text:
                if newlineRun >= 2 {
                    paragraphs.append([])
                } else if newlineRun == 1 {
                    paragraphs[paragraphs.count - 1].append(.newline)
                }
                newlineRun = 0
                paragraphs[paragraphs.count - 1].append(segment)
            }
        }

        return paragraphs.map { paragraph in
            var output = ""
            var pending: (text: String, url: URL?)?
            func flush() {
                guard let current = pending else { return }
                let escaped = DescriptionHTML.escapeText(current.text)
                if let url = current.url {
                    let href = url.absoluteString
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                    output += "<a href=\"\(href)\">\(escaped)</a>"
                } else {
                    output += escaped
                }
                pending = nil
            }
            for segment in paragraph {
                switch segment {
                case .newline:
                    flush()
                    output += "<br>"
                case .text(let string, let url):
                    if let current = pending, current.url == url {
                        pending = (current.text + string, url)
                    } else {
                        flush()
                        pending = (string, url)
                    }
                }
            }
            flush()
            return "<p>\(output)</p>"
        }.joined()
    }
}
