import Foundation
import Testing
@testable import PapaTodos

private func sanitized(_ html: String) -> String {
    DescriptionHTML.serialize(DescriptionHTML.sanitizedNodes(html))
}

private func flat(_ html: String, styled: Bool = false) -> String {
    String(DescriptionFlattener.flatten(DescriptionHTML.sanitizedNodes(html), styled: styled).characters)
}

struct DescriptionHTMLTests {
    // MARK: detection (matches the web's looksLikeHtml)

    @Test(arguments: ["<b>bold</b>", "a<br>b", "<p>x", "<A HREF='x'>y</A>", "<table><tr><td>1</td></tr></table>"])
    func detectsAllowListedTags(value: String) {
        #expect(DescriptionHTML.looksLikeHTML(value))
    }

    @Test(arguments: ["plain words", "3 < 5 and 7 > 2", "email <me@example.com>", "<script>x</script>", "", "a & b"])
    func plainTextIsNotHTML(value: String) {
        #expect(!DescriptionHTML.looksLikeHTML(value))
    }

    // MARK: sanitizing: things that must never survive

    @Test func scriptAndStyleAreRemovedWithTheirContent() {
        #expect(sanitized("ok<script>alert(1)</script>done") == "okdone")
        #expect(sanitized("<style>p{color:red}</style><p>hi</p>") == "<p>hi</p>")
        #expect(sanitized("<SCRIPT SRC=x></SCRIPT>text") == "text")
    }

    @Test func imagesFramesAndObjectsAreRemoved() {
        #expect(sanitized("<p>a<img src=\"https://evil/x.png\" onerror=\"alert(1)\">b</p>") == "<p>ab</p>")
        #expect(sanitized("x<iframe src=\"https://evil\">fallback</iframe>y") == "xy")
        #expect(sanitized("<object data=x>o</object><embed src=y>z") == "z")
        #expect(sanitized("<svg><circle/></svg>k") == "k")
    }

    @Test func formsAndButtonsAreUnwrappedButTheirTextIsKept() {
        #expect(sanitized("<form action=\"https://evil\"><button>Click me</button><input value=\"x\"></form>") == "Click me")
    }

    @Test func styleAndEventAttributesAreStripped() {
        #expect(sanitized("<p style=\"color:red\" onclick=\"x()\" class=\"c\" id=\"i\" data-x=\"1\">t</p>") == "<p>t</p>")
        #expect(sanitized("<a href=\"https://ok.com\" onclick=\"x()\" target=\"_blank\">go</a>") == "<a href=\"https://ok.com\">go</a>")
    }

    @Test(arguments: [
        "javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)",
        "java\nscript:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:msgbox(1)",
        "/relative/path", "#fragment", "//evil.com/x", "file:///etc/passwd", "ftp://host/x", "https://", "",
    ])
    func unsafeOrUselessLinkTargetsAreRemovedButTheTextStays(href: String) {
        let result = sanitized("<a href=\"\(href)\">label</a>")
        #expect(result == "<a>label</a>")
    }

    @Test(arguments: ["https://example.com/a?b=1", "http://example.com", "mailto:me@example.com", "tel:+61400000000"])
    func safeLinkTargetsSurvive(href: String) {
        let result = sanitized("<a href=\"\(href)\">label</a>")
        #expect(result.contains("href=\""))
        #expect(result.contains("label"))
    }

    // MARK: parsing quirks

    @Test func decodesEntitiesAndLeavesUnknownOnesAlone() {
        #expect(DescriptionHTML.decodeEntities("a &amp; b &lt;i&gt; &#39;q&#39; &#x27;r&#x27; &nbsp;|") == "a & b <i> 'q' 'r' \u{00A0}|")
        #expect(DescriptionHTML.decodeEntities("fish &chips; & more") == "fish &chips; & more")
        #expect(sanitized("<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
    }

    @Test func toleratesUnclosedAndImpliedEndTags() {
        #expect(sanitized("<p>one<p>two") == "<p>one</p><p>two</p>")
        #expect(sanitized("<ul><li>a<li>b</ul>") == "<ul><li>a</li><li>b</li></ul>")
        #expect(sanitized("<b>bold <i>both</b> still") == "<b>bold <i>both</i></b> still")
        #expect(sanitized("stray </p> close") == "stray  close")
    }

    @Test func dropsCommentsAndKeepsLoneAngleBrackets() {
        #expect(sanitized("a<!-- hidden -->b") == "ab")
        #expect(sanitized("<p>3 < 5</p>") == "<p>3 &lt; 5</p>")
    }

    @Test func survivesMalformedInputWithoutCrashing() {
        for input in ["<", "<<>>", "<a href=", "<a href=\"unterminated", "<p", "</", "&", "&#", "<!--", "<!", "<a\u{0}b>x</a>", String(repeating: "<div>", count: 500)] {
            _ = DescriptionHTML.sanitizedNodes(input)
        }
    }

    // MARK: helpers

    @Test func plainTextCollapsesBlocksAndKeepsPlainDescriptionsAsIs() {
        #expect(DescriptionHTML.plainText("<p>Take out</p><p>the&nbsp;bins</p>") == "Take out the bins")
        #expect(DescriptionHTML.plainText("  just text\nwith lines  ") == "just text\nwith lines")
        #expect(DescriptionHTML.plainText(nil) == "")
        #expect(DescriptionHTML.plainText("<ul><li>a</li><li>b</li></ul>") == "a b")
    }

    @Test func meaningfulContentNeedsTextOrATable() {
        func meaningful(_ html: String) -> Bool {
            DescriptionHTML.hasMeaningfulContent(DescriptionHTML.sanitizedNodes(html))
        }
        #expect(!meaningful("<p>&nbsp;</p><br>"))
        #expect(!meaningful("<div> </div>"))
        #expect(meaningful("<p>hi</p>"))
        #expect(meaningful("<table><tr><td></td></tr></table>"))
    }
}

struct DescriptionFlattenerTests {
    @Test func paragraphsAreSeparatedByBlankLinesAndBreaksByNewlines() {
        #expect(flat("<p>one</p><p>two<br>three</p>") == "one\n\ntwo\nthree")
    }

    @Test func browserStyleDivLinesStayTight() {
        #expect(flat("line1<div>line2</div><div>line3</div>") == "line1\nline2\nline3")
    }

    @Test func listsUseBulletsAndNumbersWithNestingIndentation() {
        #expect(flat("<ul><li>a</li><li>b</li></ul>") == "• a\n• b")
        #expect(flat("<ol><li>x</li><li>y</li><li>z</li></ol>") == "1. x\n2. y\n3. z")
        #expect(flat("<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>") == "• a\n    • a1\n• b")
    }

    @Test func headingsQuotesRulesAndCodeKeepTheirStructure() {
        #expect(flat("<h2>Title</h2><p>body</p>") == "Title\n\nbody")
        #expect(flat("<blockquote>quoted<br>line two</blockquote>") == "│ quoted\n│ line two")
        #expect(flat("<p>a</p><hr><p>b</p>") == "a\n\n────────\n\nb")
        #expect(flat("<pre>  keep\n    this</pre>") == "keep\n    this")
    }

    @Test func tablesBecomeRowsOfCells() {
        let html = "<table><thead><tr><th>Who</th><th>What</th></tr></thead><tbody><tr><td>Mum</td><td>Bins</td></tr><tr><td>Dad</td><td>Car</td></tr></tbody></table>"
        #expect(flat(html) == "Who | What\nMum | Bins\nDad | Car")
    }

    @Test func linksKeepTheirTarget() {
        let text = DescriptionFlattener.flatten(DescriptionHTML.sanitizedNodes("see <a href=\"https://example.com/x\">the site</a> now"), styled: false)
        let linked = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0.absoluteString) } }
        #expect(linked.count == 1)
        #expect(linked.first?.0 == "the site")
        #expect(linked.first?.1 == "https://example.com/x")
    }

    @Test func emphasisIsMarkedOnlyWhenStyled() {
        let html = "<p><strong>bold</strong> <em>slant</em> <code>mono</code></p>"
        let styledText = DescriptionFlattener.flatten(DescriptionHTML.sanitizedNodes(html), styled: true)
        let intents = styledText.runs.compactMap { $0.inlinePresentationIntent }
        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains(.emphasized))
        #expect(intents.contains(.code))

        let plainText = DescriptionFlattener.flatten(DescriptionHTML.sanitizedNodes(html), styled: false)
        #expect(plainText.runs.allSatisfy { $0.inlinePresentationIntent == nil })
        #expect(String(plainText.characters) == "bold slant mono")
    }

    @Test func emptyAndWhitespaceOnlyInputFlattenToNothing() {
        #expect(flat("") == "")
        #expect(flat("<p> </p><div>\n</div>") == "")
    }
}

struct DescriptionEditingTests {
    private func linked(_ text: String, link label: String, to url: String) -> AttributedString {
        var result = AttributedString(text)
        if let range = result.range(of: label) { result[range].link = URL(string: url) }
        return result
    }

    // MARK: loading

    @Test func plainTextLoadsUntouchedAndUnprotected() {
        let loaded = DescriptionEditing.load("Buy milk\nand eggs")
        #expect(String(loaded.text.characters) == "Buy milk\nand eggs")
        #expect(!loaded.isProtected)
    }

    @Test func emptyDescriptionsLoadEmpty() {
        for value: String? in [nil, "", "  \n "] {
            let loaded = DescriptionEditing.load(value)
            #expect(loaded.text.characters.isEmpty)
            #expect(!loaded.isProtected)
        }
    }

    @Test(arguments: [
        "<p>Just <a href=\"https://example.com\">a link</a></p>",
        "line1<div>line2</div><br>line3",
        "<span>plain</span> <a href=\"mailto:a@b.co\">mail</a>",
    ])
    func linksAndLineBreaksAreEditableWithoutProtection(html: String) {
        #expect(!DescriptionEditing.load(html).isProtected)
    }

    @Test(arguments: [
        "<ul><li>a</li></ul>", "<ol><li>a</li></ol>", "<h2>T</h2>", "<table><tr><td>1</td></tr></table>",
        "<p><b>bold</b></p>", "<em>x</em>", "<u>x</u>", "<blockquote>q</blockquote>", "<pre>c</pre>", "<code>c</code>", "a<hr>b",
    ])
    func structureTheEditorCannotHoldIsProtected(html: String) {
        #expect(DescriptionEditing.load(html).isProtected)
    }

    @Test func protectedDescriptionsStillOfferAnExplicitFlattenedEditableText() {
        let text = DescriptionEditing.simplifiedText(from: "<ul><li>eggs</li><li>milk</li></ul><p><b>Note</b></p>")
        #expect(String(text.characters) == "• eggs\n• milk\n\nNote")
    }

    // MARK: storing

    @Test func plainTextWithoutLinksIsStoredAsPlainText() {
        #expect(DescriptionEditing.storageValue(for: AttributedString("  Take out bins\nthen recycle  ")) == "Take out bins\nthen recycle")
    }

    @Test func emptyOrWhitespaceStoresNothing() {
        #expect(DescriptionEditing.storageValue(for: AttributedString()) == nil)
        #expect(DescriptionEditing.storageValue(for: AttributedString(" \n\n ")) == nil)
    }

    @Test func textWithALinkIsStoredAsSanitizedHTML() {
        let text = linked("See the roster for details", link: "the roster", to: "https://example.com/roster")
        #expect(DescriptionEditing.storageValue(for: text) == "<p>See <a href=\"https://example.com/roster\">the roster</a> for details</p>")
    }

    @Test func blankLinesBecomeParagraphsAndSingleNewlinesBecomeBreaks() {
        var text = linked("First line\nsecond line\n\nNew paragraph with link", link: "link", to: "https://example.com")
        text += AttributedString("")
        #expect(DescriptionEditing.storageValue(for: text) == "<p>First line<br>second line</p><p>New paragraph with <a href=\"https://example.com\">link</a></p>")
    }

    @Test func specialCharactersAreEscapedInStoredHTML() {
        let text = linked("R&D <team> says \"hi\" — see docs", link: "docs", to: "https://example.com/?a=1&b=2")
        let stored = DescriptionEditing.storageValue(for: text) ?? ""
        #expect(stored.contains("R&amp;D &lt;team&gt;"))
        #expect(stored.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        #expect(!stored.contains("<team>"))
    }

    @Test func unsafeLinkTargetsAreNeverStoredAsLinks() {
        var text = AttributedString("click me")
        text.link = URL(string: "javascript:alert(1)")
        #expect(DescriptionEditing.storageValue(for: text) == "click me")
        text.link = URL(string: "file:///etc/passwd")
        #expect(DescriptionEditing.storageValue(for: text) == "click me")
    }

    @Test func plainTextThatLooksLikeHTMLIsStoredEscapedSoTheWebShowsItLiterally() {
        let stored = DescriptionEditing.storageValue(for: AttributedString("use <b> for bold")) ?? ""
        #expect(stored == "<p>use &lt;b&gt; for bold</p>")
        // and it reads back as the same text:
        #expect(String(DescriptionEditing.load(stored).text.characters) == "use <b> for bold")
    }

    // MARK: round trips

    @Test func linkDescriptionsAreStableAcrossLoadAndStore() throws {
        let original = linked("Call the vet at the number below\n\nBook via the site", link: "the site", to: "https://example.com/vet")
        let stored = try #require(DescriptionEditing.storageValue(for: original))

        let reloaded = DescriptionEditing.load(stored)
        #expect(!reloaded.isProtected)
        #expect(String(reloaded.text.characters) == "Call the vet at the number below\n\nBook via the site")

        let restored = DescriptionEditing.storageValue(for: reloaded.text)
        #expect(restored == stored)
    }

    @Test func sanitizingTheStoredValueChangesNothing() throws {
        let original = linked("a <b>tag</b> & a link", link: "link", to: "https://example.com")
        let stored = try #require(DescriptionEditing.storageValue(for: original))
        #expect(DescriptionHTML.serialize(DescriptionHTML.sanitizedNodes(stored)) == stored)
    }
}
