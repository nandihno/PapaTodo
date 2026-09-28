import Foundation

/// Bullet-list editing for the description editor. In the editor a bullet is simply a line
/// that starts with "• " (the same text `DescriptionFlattener` produces for `<ul><li>`), and
/// `DescriptionEditing` stores such lines as a `<ul>` list.
///
/// Positions are character offsets into the text, so the view can translate to and from the
/// editor's selection without holding on to indices across mutations.
nonisolated enum DescriptionBullets {
    static let marker = "• "

    /// Up to this many characters in one change are treated as typing (the editor batches
    /// fast keystrokes). Anything longer is a paste or a replaced description, and only its
    /// last character can trigger a rule, so a pasted list is never re-bulleted.
    private static let typingBatch = 3

    struct Result: Equatable {
        var text: AttributedString
        var selection: Range<Int>
    }

    // MARK: toggle

    /// Turns every line touched by `selection` into a bullet, or, when they already all are,
    /// back into plain lines.
    static func toggle(_ text: AttributedString, selection: Range<Int>) -> Result {
        let characters = Array(text.characters)
        let lower = min(selection.lowerBound, characters.count)
        let upper = min(max(selection.upperBound, lower), characters.count)
        // A selection ending right after a newline doesn't reach into the next line.
        let last = upper > lower ? upper - 1 : lower
        let starts = lineStarts(characters).filter { $0 >= lineStart(of: lower, in: characters) && $0 <= last }
        let removing = starts.allSatisfy { markerLength(at: $0, in: characters) > 0 }

        var result = text
        var newLower = lower
        var newUpper = upper
        // Last line first, so earlier offsets stay valid.
        for start in starts.reversed() {
            let length = markerLength(at: start, in: characters)
            if removing {
                result.removeSubrange(range(start..<(start + length), in: result))
                newLower = shifted(newLower, removing: length, at: start)
                newUpper = shifted(newUpper, removing: length, at: start)
            } else if length == 0 {
                result.insert(AttributedString(marker), at: index(start, in: result))
                if newLower >= start { newLower += marker.count }
                if newUpper >= start { newUpper += marker.count }
            }
        }
        return Result(text: result, selection: newLower..<newUpper)
    }

    // MARK: typing rules

    /// Applies the list rules to newly typed text, like Notes:
    /// - Return on a bullet starts a new bullet;
    /// - Return on an empty bullet ends the list (the bullet is removed);
    /// - "- " or "* " at the start of a line becomes a bullet.
    ///
    /// The editor can report several typed characters as one change, so the inserted text is
    /// found from `caret` (where the editor says the cursor is now), which also disambiguates
    /// typing a character next to an identical one. Without a caret only a single inserted
    /// character is recognised; see `typingBatch` for longer insertions. Returns nil when nothing was inserted or no rule applies.
    static func afterTyping(old: AttributedString, new: AttributedString, caret: Int?) -> Result? {
        let before = Array(old.characters)
        let after = Array(new.characters)
        let count = after.count - before.count
        guard count > 0 else { return nil }

        let inserted: Range<Int>
        if let caret, caret >= count, caret <= after.count,
           after[..<(caret - count)].elementsEqual(before[..<(caret - count)]),
           after[caret...].elementsEqual(before[(caret - count)...]) {
            inserted = (caret - count)..<caret
        } else if count == 1, let position = insertedPosition(before: before, after: after) {
            inserted = position..<(position + 1)
        } else {
            return nil
        }
        let candidates = inserted.count <= typingBatch ? inserted : (inserted.upperBound - 1)..<inserted.upperBound
        for position in candidates {
            if let result = rule(at: position, in: after, text: new, caret: inserted.upperBound) { return result }
        }
        return nil
    }

    private static func rule(at position: Int, in after: [Character], text new: AttributedString, caret: Int) -> Result? {
        switch after[position] {
        case "\n":
            let start = lineStart(of: position, in: after)
            let length = markerLength(at: start, in: after)
            guard length > 0 else { return nil }
            let content = after[(start + length)..<position]
            var result = new
            if content.allSatisfy(\.isWhitespace) {
                // An empty bullet: drop it and the new line, leaving an ordinary empty line.
                result.removeSubrange(range(start..<(position + 1), in: result))
                let caret = caret - (position + 1 - start)
                return Result(text: result, selection: caret..<caret)
            }
            result.insert(AttributedString(marker), at: index(position + 1, in: result))
            let caret = caret + marker.count
            return Result(text: result, selection: caret..<caret)
        case " ":
            let start = lineStart(of: position, in: after)
            guard position == start + 1, after[start] == "-" || after[start] == "*" else { return nil }
            var result = new
            result.replaceSubrange(range(start..<(position + 1), in: result), with: AttributedString(marker))
            return Result(text: result, selection: caret..<caret)
        default:
            return nil
        }
    }

    /// Where the one extra character in `after` was inserted: the first difference, moved back
    /// to the start of a run of the same character (so Return typed before an existing blank
    /// line continues the line above).
    private static func insertedPosition(before: [Character], after: [Character]) -> Int? {
        var position = zip(before, after).prefix { $0 == $1 }.count
        while position > 0, after[position - 1] == after[position] { position -= 1 }
        let isInsertion = after[..<position].elementsEqual(before[..<position])
            && after[(position + 1)...].elementsEqual(before[position...])
        return isInsertion ? position : nil
    }

    // MARK: lines

    /// Characters taken up by the bullet marker at the start of a line: "• " or a bare "•".
    static func markerLength(at start: Int, in characters: [Character]) -> Int {
        guard start < characters.count, characters[start] == "•" else { return 0 }
        return start + 1 < characters.count && characters[start + 1] == " " ? 2 : 1
    }

    private static func lineStarts(_ characters: [Character]) -> [Int] {
        [0] + characters.indices.filter { characters[$0] == "\n" }.map { $0 + 1 }
    }

    private static func lineStart(of position: Int, in characters: [Character]) -> Int {
        var start = min(position, characters.count)
        while start > 0, characters[start - 1] != "\n" { start -= 1 }
        return start
    }

    private static func shifted(_ position: Int, removing length: Int, at start: Int) -> Int {
        position > start ? position - min(length, position - start) : position
    }

    // MARK: offsets

    static func index(_ offset: Int, in text: AttributedString) -> AttributedString.Index {
        text.characters.index(text.startIndex, offsetBy: offset)
    }

    static func range(_ offsets: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        index(offsets.lowerBound, in: text)..<index(offsets.upperBound, in: text)
    }

    static func offset(of index: AttributedString.Index, in text: AttributedString) -> Int? {
        guard index >= text.startIndex, index <= text.endIndex else { return nil }
        return text.characters.distance(from: text.startIndex, to: index)
    }
}
