import Foundation

/// Converts between a stored description and what the native editor can hold: plain text
/// with links and bullet lists. Everything else the sanitizer allows (numbered lists,
/// headings, tables, emphasis, quotes, code) is rendered for reading but *protected* from silent loss: the editor only
/// touches such a description if the user explicitly chooses to simplify it.
nonisolated enum DescriptionEditing {
    struct Loaded: Equatable {
        var text: AttributedString
        /// The stored description has structure the editor can't represent.
        var isProtected: Bool
    }

    /// Tags the editor can round-trip without losing anything (besides a simple `<ul>`).
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

    /// Links, line breaks and simple bullet lists (a top-level `<ul>` of `<li>`s holding text
    /// and links). Numbered or nested lists, and lists inside other blocks, stay protected.
    private static func isRepresentable(_ nodes: [DescriptionHTML.Node]) -> Bool {
        nodes.allSatisfy { node in
            guard case .element(let element) = node, element.tag == "ul" else { return isPlainContent(node) }
            return element.children.allSatisfy { child in
                switch child {
                case .text(let text): text.allSatisfy(\.isWhitespace)
                case .element(let item): item.tag == "li" && item.children.allSatisfy(isPlainContent)
                }
            }
        }
    }

    private static func isPlainContent(_ node: DescriptionHTML.Node) -> Bool {
        switch node {
        case .text: true
        case .element(let element):
            representableTags.contains(element.tag) && element.children.allSatisfy(isPlainContent)
        }
    }

    // MARK: storing

    private enum Segment {
        case text(String, URL?)
        case newline
    }

    /// The value to store, or nil for an empty description. Text with no links or bullets is
    /// stored as plain text; otherwise it is stored as sanitized HTML (`<p>`, `<br>`,
    /// `<a href>`, and `<ul><li>` for lines starting with "• "). Plain text that would be
    /// mistaken for HTML (it contains something like `<b>`) is stored as escaped HTML so it
    /// displays literally.
    static func storageValue(for text: AttributedString) -> String? {
        let segments = trimmed(segments(of: text))
        guard !segments.isEmpty else { return nil }

        let lines = lines(of: segments)
        let hasLinks = segments.contains { if case .text(_, let url) = $0 { url != nil } else { false } }
        let hasBullets = lines.contains { $0.isBullet }
        let plain = segments.map { segment -> String in
            switch segment {
            case .text(let string, _): string
            case .newline: "\n"
            }
        }.joined()

        if !hasLinks && !hasBullets && !DescriptionHTML.looksLikeHTML(plain) {
            return plain
        }
        let html = html(from: lines)
        return html.isEmpty ? nil : html
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

    private struct Line {
        var runs: [(text: String, url: URL?)]
        var isBullet = false
        /// An empty line, or a bullet with nothing after the marker: separates blocks.
        var isBlank: Bool {
            isBullet ? runs.allSatisfy { $0.text.allSatisfy(\.isWhitespace) } : runs.isEmpty
        }
    }

    /// Splits segments into lines and strips the bullet marker from bullet lines.
    private static func lines(of segments: [Segment]) -> [Line] {
        var lines = [Line(runs: [])]
        for segment in segments {
            switch segment {
            case .newline: lines.append(Line(runs: []))
            case .text(let string, let url): lines[lines.count - 1].runs.append((string, url))
            }
        }
        return lines.map { line in
            let characters = Array(line.runs.map(\.text).joined())
            var remaining = DescriptionBullets.markerLength(at: 0, in: characters)
            guard remaining > 0 else { return line }
            var runs = line.runs
            while remaining > 0, !runs.isEmpty {
                let dropped = min(remaining, runs[0].text.count)
                runs[0].text.removeFirst(dropped)
                remaining -= dropped
                if runs[0].text.isEmpty { runs.removeFirst() }
            }
            return Line(runs: runs, isBullet: true)
        }
    }

    private static func html(from lines: [Line]) -> String {
        enum Block {
            case paragraph([Line])
            case list([Line])
        }
        var blocks: [Block] = []
        var current: Block?
        func finish() {
            if let block = current { blocks.append(block) }
            current = nil
        }
        for line in lines {
            if line.isBlank {
                finish()
            } else if line.isBullet {
                if case .list(let items) = current { current = .list(items + [line]) } else { finish(); current = .list([line]) }
            } else {
                if case .paragraph(let rows) = current { current = .paragraph(rows + [line]) } else { finish(); current = .paragraph([line]) }
            }
        }
        finish()

        return blocks.map { block in
            switch block {
            case .paragraph(let rows):
                "<p>" + rows.map { inlineHTML($0.runs) }.joined(separator: "<br>") + "</p>"
            case .list(let items):
                "<ul>" + items.map { "<li>" + inlineHTML($0.runs) + "</li>" }.joined() + "</ul>"
            }
        }.joined()
    }

    /// One line's text, escaped, with adjacent runs to the same link merged into one `<a>`.
    private static func inlineHTML(_ runs: [(text: String, url: URL?)]) -> String {
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
        for run in runs {
            if let current = pending, current.url == run.url {
                pending = (current.text + run.text, run.url)
            } else {
                flush()
                pending = run
            }
        }
        flush()
        return output
    }
}
