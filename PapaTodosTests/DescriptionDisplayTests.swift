import Foundation
import Testing
@testable import PapaTodos

struct DescriptionDisplayTests {
    private func links(in text: AttributedString) -> [String] {
        text.runs.compactMap { $0.link?.absoluteString }
    }

    @Test func emptyOrMeaninglessDescriptionsHaveNothingToShow() {
        for value: String? in [nil, "", "  ", "<p>&nbsp;</p>", "<div> </div><br>"] {
            #expect(DescriptionDisplay.attributed(from: value) == nil, "\(value ?? "nil")")
        }
    }

    @Test func aScriptTagIsNotAnAllowListedTagSoItIsShownAsInertText() throws {
        // Same as the web app: without an allowed tag the value is plain text, displayed literally.
        let text = try #require(DescriptionDisplay.attributed(from: "<script>alert(1)</script>"))
        #expect(String(text.characters) == "<script>alert(1)</script>")
        #expect(links(in: text).isEmpty)
    }

    @Test func plainTextIsShownAsIsWithTappableWebAddresses() throws {
        let text = try #require(DescriptionDisplay.attributed(from: "Book at https://example.com/vet today.\nCall 0400 000 000."))
        #expect(String(text.characters) == "Book at https://example.com/vet today.\nCall 0400 000 000.")
        #expect(links(in: text) == ["https://example.com/vet"])
    }

    @Test func plainTextDoesNotTurnNonWebSchemesIntoLinks() throws {
        let text = try #require(DescriptionDisplay.attributed(from: "ftp://files.example.com and javascript:alert(1)"))
        #expect(links(in: text).isEmpty)
    }

    @Test func htmlKeepsStructureEmphasisAndLinks() throws {
        let html = "<h2>Plan</h2><ul><li>Buy <b>milk</b></li><li><a href=\"https://example.com\">List</a></li></ul>"
        let text = try #require(DescriptionDisplay.attributed(from: html))
        #expect(String(text.characters) == "Plan\n\n• Buy milk\n• List")
        #expect(links(in: text) == ["https://example.com"])
        #expect(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test func maliciousHTMLRendersAsHarmlessText() throws {
        let html = "<p>hi<script>alert(1)</script><a href=\"javascript:alert(2)\">tap</a><img src=x onerror=alert(3)></p>"
        let text = try #require(DescriptionDisplay.attributed(from: html))
        #expect(String(text.characters) == "hitap")
        #expect(links(in: text).isEmpty)
    }
}
