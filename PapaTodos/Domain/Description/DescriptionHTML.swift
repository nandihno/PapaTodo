import Foundation

/// A small allow-list HTML parser and sanitizer for chore descriptions.
///
/// PapaBoard stores descriptions as either plain text or HTML cleaned by DOMPurify with
/// a fixed tag/attribute allow-list (`src/lib/descriptionHtml.js`). There is no DOM on
/// iOS, and Apple's HTML importer is heavyweight and WebKit-backed, so this parses
/// directly into a tree, drops everything outside the same allow-list, and keeps only
/// links that are safe to open (http, https, mailto, tel).
nonisolated enum DescriptionHTML {
    struct Element: Equatable, Sendable {
        var tag: String
        var attributes: [String: String]
        var children: [Node]
    }

    indirect enum Node: Equatable, Sendable {
        case text(String)
        case element(Element)
    }

    // MARK: allow-list (mirrors descriptionHtml.js)

    static let allowedTags: Set<String> = [
        "a", "b", "blockquote", "br", "code", "div", "em", "h1", "h2", "h3", "h4", "hr", "i", "li", "ol",
        "p", "pre", "span", "strong", "table", "tbody", "td", "th", "thead", "tr", "u", "ul",
    ]
    static let allowedAttributes: Set<String> = ["colspan", "href", "rel", "rowspan", "title"]
    /// Tags removed together with everything inside them (other unknown tags are unwrapped).
    private static let dropWithContent: Set<String> = [
        "script", "style", "iframe", "object", "embed", "svg", "noscript", "template", "head", "title",
        "textarea", "select", "math",
    ]
    private static let voidTags: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr",
    ]
    private static let rawTextTags: Set<String> = ["script", "style"]
    private static let blockTags: Set<String> = [
        "div", "ul", "ol", "table", "h1", "h2", "h3", "h4", "blockquote", "pre", "hr", "p",
    ]

    // MARK: detection

    /// Same test as the web's `looksLikeHtml`: does the text contain an allowed tag?
    static func looksLikeHTML(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.range(
            of: #"</?(?:a|b|blockquote|br|code|div|em|h[1-4]|hr|i|li|ol|p|pre|span|strong|table|tbody|td|th|thead|tr|u|ul)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: URLs

    /// Only absolute http, https, mailto and tel URLs are usable. The web's allow-list also
    /// admits relative URLs, which mean nothing in a native app, so they are dropped too.
    static func safeURL(_ raw: String) -> URL? {
        // Browsers ignore whitespace/control characters inside a scheme ("java\tscript:").
        let cleaned = String(raw.unicodeScalars.filter { !$0.properties.isWhitespace && $0.value >= 0x20 && $0.value != 0x7F })
        let lower = cleaned.lowercased()
        guard ["http://", "https://", "mailto:", "tel:"].contains(where: lower.hasPrefix) else { return nil }
        guard let url = URL(string: cleaned) else { return nil }
        if lower.hasPrefix("http"), url.host()?.isEmpty ?? true { return nil }
        return url
    }

    // MARK: parse + sanitize

    /// Parses `html` and returns only allow-listed content.
    static func sanitizedNodes(_ html: String) -> [Node] {
        sanitize(parse(html))
    }

    static func parse(_ html: String) -> [Node] {
        var parser = Parser(Array(html))
        return parser.run()
    }

    private static func sanitize(_ nodes: [Node]) -> [Node] {
        var output: [Node] = []
        for node in nodes {
            switch node {
            case .text:
                output.append(node)
            case .element(var element):
                if allowedTags.contains(element.tag) {
                    element.attributes = element.attributes.filter { allowedAttributes.contains($0.key) }
                    if element.tag == "a" {
                        if let href = element.attributes["href"], let url = safeURL(href) {
                            element.attributes["href"] = url.absoluteString
                        } else {
                            element.attributes["href"] = nil
                        }
                    } else {
                        element.attributes["href"] = nil
                    }
                    element.children = sanitize(element.children)
                    output.append(.element(element))
                } else if !dropWithContent.contains(element.tag) {
                    output.append(contentsOf: sanitize(element.children))
                }
            }
        }
        return output
    }

    // MARK: serialize

    static func serialize(_ nodes: [Node]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let text):
                return escapeText(text)
            case .element(let element):
                var open = "<\(element.tag)"
                for key in element.attributes.keys.sorted() {
                    open += " \(key)=\"\(escapeAttribute(element.attributes[key] ?? ""))\""
                }
                if voidTags.contains(element.tag) { return open + ">" }
                return open + ">" + serialize(element.children) + "</\(element.tag)>"
            }
        }.joined()
    }

    static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: text helpers

    /// Visible text with block boundaries as spaces, whitespace collapsed. Non-HTML
    /// descriptions are returned trimmed and unchanged (like `descriptionToPlainText`).
    static func plainText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard looksLikeHTML(trimmed) else { return trimmed }
        return textContent(sanitizedNodes(trimmed))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func textContent(_ nodes: [Node]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let text): text
            case .element(let element):
                blockTags.contains(element.tag) || ["li", "tr", "td", "th", "br"].contains(element.tag)
                    ? " " + textContent(element.children) + " "
                    : textContent(element.children)
            }
        }.joined()
    }

    /// Whether the description has any visible text or a table (`hasMeaningfulDescription`).
    static func hasMeaningfulContent(_ nodes: [Node]) -> Bool {
        for node in nodes {
            switch node {
            case .text(let text):
                if !text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            case .element(let element):
                if element.tag == "table" || hasMeaningfulContent(element.children) { return true }
            }
        }
        return false
    }

    // MARK: tokenizer / tree builder

    private struct Parser {
        struct Frame {
            var tag: String
            var attributes: [String: String]
            var children: [Node] = []
        }

        let chars: [Character]
        var index = 0
        var stack: [Frame] = [Frame(tag: "", attributes: [:])]

        init(_ chars: [Character]) { self.chars = chars }

        mutating func run() -> [Node] {
            var text = ""
            func flush(_ parser: inout Parser) {
                if !text.isEmpty {
                    parser.stack[parser.stack.count - 1].children.append(.text(DescriptionHTML.decodeEntities(text)))
                    text = ""
                }
            }
            while index < chars.count {
                let char = chars[index]
                guard char == "<" else {
                    text.append(char)
                    index += 1
                    continue
                }
                if matches("<!--") {
                    flush(&self)
                    skip(past: "-->")
                } else if matches("<!") || matches("<?") {
                    flush(&self)
                    skip(past: ">")
                } else if let next = peek(1), next == "/", let after = peek(2), after.isLetter {
                    flush(&self)
                    parseEndTag()
                } else if let next = peek(1), next.isLetter {
                    flush(&self)
                    parseStartTag()
                } else {
                    text.append(char) // a lone "<" such as "3 < 5"
                    index += 1
                }
            }
            flush(&self)
            while stack.count > 1 { closeTop() }
            return stack[0].children
        }

        private func peek(_ offset: Int) -> Character? {
            index + offset < chars.count ? chars[index + offset] : nil
        }

        private func matches(_ literal: String) -> Bool {
            let needle = Array(literal)
            guard index + needle.count <= chars.count else { return false }
            return Array(chars[index..<index + needle.count]) == needle
        }

        private mutating func skip(past literal: String) {
            let needle = Array(literal)
            while index < chars.count {
                if matches(literal) { index += needle.count; return }
                index += 1
            }
        }

        private mutating func closeTop() {
            let frame = stack.removeLast()
            stack[stack.count - 1].children.append(.element(.init(tag: frame.tag, attributes: frame.attributes, children: frame.children)))
        }

        private mutating func parseEndTag() {
            index += 2
            var name = ""
            while index < chars.count, chars[index] != ">", !chars[index].isWhitespace { name.append(chars[index]); index += 1 }
            skip(past: ">")
            let tag = name.lowercased()
            guard let position = stack.lastIndex(where: { $0.tag == tag }), position > 0 else { return }
            while stack.count > position { closeTop() }
        }

        private mutating func parseStartTag() {
            index += 1
            var name = ""
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "-" {
                name.append(chars[index]); index += 1
            }
            let tag = name.lowercased()
            var attributes: [String: String] = [:]
            var selfClosing = false

            attributeLoop: while index < chars.count {
                while index < chars.count, chars[index].isWhitespace { index += 1 }
                guard index < chars.count else { break }
                if chars[index] == ">" { index += 1; break }
                if chars[index] == "/" {
                    selfClosing = true; index += 1; continue
                }
                var key = ""
                while index < chars.count, !chars[index].isWhitespace, chars[index] != "=", chars[index] != ">", chars[index] != "/" {
                    key.append(chars[index]); index += 1
                }
                while index < chars.count, chars[index].isWhitespace { index += 1 }
                var value = ""
                if index < chars.count, chars[index] == "=" {
                    index += 1
                    while index < chars.count, chars[index].isWhitespace { index += 1 }
                    if index < chars.count, chars[index] == "\"" || chars[index] == "'" {
                        let quote = chars[index]; index += 1
                        while index < chars.count, chars[index] != quote { value.append(chars[index]); index += 1 }
                        index += 1
                    } else {
                        while index < chars.count, !chars[index].isWhitespace, chars[index] != ">" { value.append(chars[index]); index += 1 }
                    }
                }
                if !key.isEmpty { attributes[key.lowercased()] = DescriptionHTML.decodeEntities(value) }
                continue attributeLoop
            }

            if DescriptionHTML.rawTextTags.contains(tag) {
                skipRawText(closing: tag)
                return
            }
            applyImpliedEndTags(for: tag)
            if DescriptionHTML.voidTags.contains(tag) || selfClosing {
                stack[stack.count - 1].children.append(.element(.init(tag: tag, attributes: attributes, children: [])))
            } else {
                stack.append(Frame(tag: tag, attributes: attributes))
            }
        }

        private mutating func skipRawText(closing tag: String) {
            let close = Array("</\(tag)")
            while index < chars.count {
                if index + close.count <= chars.count,
                   String(chars[index..<index + close.count]).lowercased() == String(close) {
                    skip(past: ">")
                    return
                }
                index += 1
            }
        }

        /// The small subset of HTML's optional-end-tag rules real descriptions rely on.
        private mutating func applyImpliedEndTags(for tag: String) {
            func top() -> String { stack[stack.count - 1].tag }
            if DescriptionHTML.blockTags.contains(tag) || tag == "li" {
                if top() == "p" { closeTop() }
            }
            switch tag {
            case "li": if top() == "li" { closeTop() }
            case "td", "th": if top() == "td" || top() == "th" { closeTop() }
            case "tr":
                if top() == "td" || top() == "th" { closeTop() }
                if top() == "tr" { closeTop() }
            case "tbody", "thead":
                if top() == "td" || top() == "th" { closeTop() }
                if top() == "tr" { closeTop() }
            default: break
            }
        }
    }

    // MARK: entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·", "deg": "°", "euro": "€",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            guard char == "&", let semicolon = text[index...].firstIndex(of: ";"),
                  text.distance(from: index, to: semicolon) <= 10 else {
                result.append(char)
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semicolon])
            if let replacement = decode(entity: body) {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func decode(entity body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value = digits.lowercased().hasPrefix("x")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[body]
    }
}
