import Foundation

/// Turns sanitized description nodes into an `AttributedString`, keeping the structure the
/// web sanitizer allows (paragraphs, line breaks, emphasis, links, lists, headings,
/// blockquotes, code/preformatted text, rules, tables) as readable text.
///
/// `styled: true` (display) marks bold/italic/code with `inlinePresentationIntent`;
/// `styled: false` (used when a description is handed to the editor as plain text) keeps
/// only the text, line structure and links.
nonisolated struct DescriptionFlattener {
    private struct Style {
        var bold = false
        var italic = false
        var code = false
        var link: URL?
    }

    private struct Block {
        var text: AttributedString
        /// Blocks sharing a group id are separated by a single newline, others by a blank line.
        var group: Int?
    }

    private struct ListContext {
        var ordered: Bool
        var counter = 0
    }

    /// Consecutive `<div>` lines (how a browser's editable box stores line breaks) stay tight.
    private static let divGroup = -1

    private let styled: Bool
    private var blocks: [Block] = []
    private var inline = AttributedString()
    private var listStack: [ListContext] = []
    private var pendingPrefix: String?
    private var quoteDepth = 0
    private var nextGroup = 0
    private var preformatted = false

    private init(styled: Bool) { self.styled = styled }

    static func flatten(_ nodes: [DescriptionHTML.Node], styled: Bool) -> AttributedString {
        var flattener = DescriptionFlattener(styled: styled)
        flattener.walk(nodes, style: Style(), group: nil)
        flattener.flush(group: nil)
        return flattener.joined()
    }

    // MARK: walking

    private mutating func walk(_ nodes: [DescriptionHTML.Node], style: Style, group: Int?) {
        for node in nodes {
            switch node {
            case .text(let text):
                appendText(text, style: style)
            case .element(let element):
                walk(element, style: style, group: group)
            }
        }
    }

    private mutating func walk(_ element: DescriptionHTML.Element, style: Style, group: Int?) {
        var style = style
        switch element.tag {
        case "br":
            inline += AttributedString("\n")
        case "a":
            if let href = element.attributes["href"], let url = URL(string: href) { style.link = url }
            walk(element.children, style: style, group: group)
        case "b", "strong":
            style.bold = true
            walk(element.children, style: style, group: group)
        case "i", "em":
            style.italic = true
            walk(element.children, style: style, group: group)
        case "code":
            style.code = true
            walk(element.children, style: style, group: group)
        case "h1", "h2", "h3", "h4":
            flush(group: group)
            style.bold = true
            walk(element.children, style: style, group: group)
            flush(group: group)
        case "div":
            flush(group: Self.divGroup)
            walk(element.children, style: style, group: group)
            flush(group: Self.divGroup)
        case "p":
            flush(group: group)
            walk(element.children, style: style, group: group)
            flush(group: group)
        case "blockquote":
            flush(group: group)
            quoteDepth += 1
            walk(element.children, style: style, group: group)
            flush(group: group)
            quoteDepth -= 1
        case "pre":
            flush(group: group)
            let wasPreformatted = preformatted
            preformatted = true
            style.code = true
            walk(element.children, style: style, group: group)
            flush(group: group)
            preformatted = wasPreformatted
        case "hr":
            flush(group: group)
            blocks.append(Block(text: AttributedString("────────"), group: group))
        case "ul", "ol":
            flush(group: group)
            // Nested lists reuse the outermost group so their items stay on adjacent lines.
            let listGroup = group ?? newGroup()
            listStack.append(ListContext(ordered: element.tag == "ol"))
            walk(element.children, style: style, group: listGroup)
            flush(group: listGroup)
            listStack.removeLast()
        case "li":
            flush(group: group)
            let depth = max(0, listStack.count - 1)
            var marker = "•"
            if var context = listStack.popLast() {
                context.counter += 1
                marker = context.ordered ? "\(context.counter)." : "•"
                listStack.append(context)
            }
            pendingPrefix = String(repeating: "    ", count: depth) + marker + " "
            walk(element.children, style: style, group: group)
            flush(group: group)
            pendingPrefix = nil
        case "table":
            flush(group: group)
            let tableGroup = group ?? newGroup()
            walk(element.children, style: style, group: tableGroup)
            flush(group: tableGroup)
        case "tr":
            flush(group: group)
            let cells = element.children.compactMap { node -> DescriptionHTML.Element? in
                if case .element(let cell) = node, cell.tag == "td" || cell.tag == "th" { return cell }
                return nil
            }
            for (position, cell) in cells.enumerated() {
                var cellStyle = style
                if cell.tag == "th" { cellStyle.bold = true }
                walk(cell.children, style: cellStyle, group: group)
                if position < cells.count - 1 { appendText(" | ", style: Style()) }
            }
            flush(group: group)
        default: // span, thead, tbody, and anything else that only wraps content
            walk(element.children, style: style, group: group)
        }
    }

    private mutating func newGroup() -> Int {
        nextGroup += 1
        return nextGroup
    }

    // MARK: text and blocks

    private mutating func appendText(_ raw: String, style: Style) {
        var text = raw
        if !preformatted {
            text = text
                .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
        }
        guard !text.isEmpty else { return }
        var piece = AttributedString(text)
        if styled {
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if style.code { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        }
        if let link = style.link { piece.link = link }
        inline += piece
    }

    private mutating func flush(group: Int?) {
        var text = Self.trimmed(inline)
        inline = AttributedString()
        guard !text.characters.isEmpty else { return }
        if let prefix = pendingPrefix {
            text = AttributedString(prefix) + text
            pendingPrefix = nil
        }
        if quoteDepth > 0 {
            text = Self.prefixingLines(of: text, with: String(repeating: "│ ", count: quoteDepth))
        }
        blocks.append(Block(text: text, group: group))
    }

    private func joined() -> AttributedString {
        var result = AttributedString()
        for (position, block) in blocks.enumerated() {
            if position > 0 {
                let tight = block.group != nil && block.group == blocks[position - 1].group
                result += AttributedString(tight ? "\n" : "\n\n")
            }
            result += block.text
        }
        return result
    }

    // MARK: helpers

    static func trimmed(_ text: AttributedString) -> AttributedString {
        let characters = text.characters
        guard let start = characters.firstIndex(where: { !$0.isWhitespace }) else { return AttributedString() }
        var end = characters.endIndex
        while end > start {
            let previous = characters.index(before: end)
            if characters[previous].isWhitespace { end = previous } else { break }
        }
        return AttributedString(text[start..<end])
    }

    /// Adds `prefix` at the start of every line. Rebuilt from slices of the original so no
    /// index is used after the string has been mutated.
    private static func prefixingLines(of text: AttributedString, with prefix: String) -> AttributedString {
        let characters = text.characters
        var result = AttributedString(prefix)
        var cursor = text.startIndex
        for index in characters.indices where characters[index] == "\n" {
            let afterNewline = characters.index(after: index)
            result += AttributedString(text[cursor..<afterNewline])
            result += AttributedString(prefix)
            cursor = afterNewline
        }
        result += AttributedString(text[cursor...])
        return result
    }
}

/// A stored description as read-only display text: plain text with tappable web addresses,
/// or sanitized HTML with its structure and emphasis kept. Nil when there is nothing to show.
nonisolated enum DescriptionDisplay {
    static func attributed(from stored: String?) -> AttributedString? {
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if DescriptionHTML.looksLikeHTML(trimmed) {
            let nodes = DescriptionHTML.sanitizedNodes(trimmed)
            guard DescriptionHTML.hasMeaningfulContent(nodes) else { return nil }
            let text = DescriptionFlattener.flatten(nodes, styled: true)
            return text.characters.isEmpty ? nil : text
        }
        return linkified(trimmed)
    }

    /// Makes web addresses in plain text tappable (http and https only).
    static func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].link = url
        }
        return result
    }
}
