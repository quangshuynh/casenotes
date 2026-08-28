//
//  MarkdownDocumentTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import Testing
@testable import CaseNotes

@MainActor
struct MarkdownDocumentTests {
    /// Convenience for asserting on block text without inspecting attributes.
    private func text(of block: MarkdownDocument.Block?) -> String? {
        switch block {
        case let .paragraph(text), let .blockQuote(text):
            String(text.characters)
        case let .heading(_, text):
            String(text.characters)
        case let .listItem(_, _, text):
            String(text.characters)
        case let .codeBlock(_, code):
            code
        case .thematicBreak, nil:
            nil
        }
    }

    @Test
    func emptySourceProducesNoBlocks() {
        #expect(MarkdownDocument("").blocks.isEmpty)
    }

    @Test
    func plainProseBecomesOneParagraphPerBlankLineSeparatedGroup() {
        let document = MarkdownDocument("First thought.\n\nSecond thought.")

        #expect(document.blocks.count == 2)
        #expect(text(of: document.blocks.first) == "First thought.")
        #expect(text(of: document.blocks.last) == "Second thought.")
    }

    @Test
    func handWrittenLineBreaksSurviveInsideAParagraph() {
        let document = MarkdownDocument("Milk\nBread\nCoffee")

        #expect(document.blocks.count == 1)
        #expect(text(of: document.blocks.first) == "Milk\nBread\nCoffee")
    }

    @Test
    func headingsCarryTheirLevel() {
        let document = MarkdownDocument("# One\n\n## Two\n\n### Three")

        #expect(document.blocks.count == 3)

        guard case let .heading(first, _) = document.blocks[0],
              case let .heading(second, _) = document.blocks[1],
              case let .heading(third, _) = document.blocks[2]
        else {
            Issue.record("Expected three headings")
            return
        }

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
        #expect(text(of: document.blocks[0]) == "One")
    }

    @Test
    func bulletedListItemsHaveNoOrdinal() {
        let document = MarkdownDocument("- Alpha\n- Beta")

        #expect(document.blocks.count == 2)

        guard case let .listItem(ordinal, depth, _) = document.blocks[0] else {
            Issue.record("Expected a list item")
            return
        }

        #expect(ordinal == nil)
        #expect(depth == 0)
        #expect(text(of: document.blocks[1]) == "Beta")
    }

    @Test
    func numberedListItemsKeepTheirOrdinal() {
        let document = MarkdownDocument("1. First\n2. Second")

        guard case let .listItem(first, _, _) = document.blocks[0],
              case let .listItem(second, _, _) = document.blocks[1]
        else {
            Issue.record("Expected two list items")
            return
        }

        #expect(first == 1)
        #expect(second == 2)
    }

    @Test
    func nestedListItemsReportTheirDepth() {
        let document = MarkdownDocument("- Alpha\n    - Nested")

        guard case let .listItem(_, outer, _) = document.blocks[0],
              case let .listItem(_, inner, _) = document.blocks[1]
        else {
            Issue.record("Expected two list items")
            return
        }

        #expect(outer == 0)
        #expect(inner == 1)
    }

    @Test
    func blockQuotesAreRecognized() {
        let document = MarkdownDocument("> Parts are on order.")

        guard case .blockQuote = document.blocks.first else {
            Issue.record("Expected a block quote")
            return
        }

        #expect(text(of: document.blocks.first) == "Parts are on order.")
    }

    @Test
    func fencedCodeBlocksKeepTheirLanguageAndSource() {
        let document = MarkdownDocument("```swift\nlet x = 1\n```")

        guard case let .codeBlock(language, code) = document.blocks.first else {
            Issue.record("Expected a code block")
            return
        }

        #expect(language == "swift")
        #expect(code == "let x = 1")
    }

    @Test
    func fencedCodeBlocksWithoutALanguageParse() {
        let document = MarkdownDocument("```\nplain\n```")

        guard case let .codeBlock(language, code) = document.blocks.first else {
            Issue.record("Expected a code block")
            return
        }

        #expect(language == nil)
        #expect(code == "plain")
    }

    @Test
    func thematicBreaksBecomeTheirOwnBlock() {
        let document = MarkdownDocument("Above\n\n---\n\nBelow")

        #expect(document.blocks.count == 3)
        #expect(document.blocks[1] == .thematicBreak)
    }

    @Test
    func inlineEmphasisIsParsedAndSyntaxRemoved() {
        let document = MarkdownDocument("Check **this** and *that*.")

        #expect(text(of: document.blocks.first) == "Check this and that.")

        guard case let .paragraph(text) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }

        let intents = text.runs.compactMap(\.inlinePresentationIntent)
        #expect(intents.contains { $0.contains(.stronglyEmphasized) })
        #expect(intents.contains { $0.contains(.emphasized) })
    }

    @Test
    func linksKeepTheirDestination() {
        let document = MarkdownDocument("See the [handbook](https://example.com).")

        guard case let .paragraph(text) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }

        let links = text.runs.compactMap(\.link)
        #expect(links.map(\.absoluteString) == ["https://example.com"])
        #expect(String(text.characters) == "See the handbook.")
    }

    @Test
    func malformedMarkdownStillYieldsReadableText() {
        let document = MarkdownDocument("**unclosed emphasis and [a broken](link")

        #expect(document.blocks.count == 1)
        #expect(
            text(of: document.blocks.first)
                == "**unclosed emphasis and [a broken](link"
        )
    }

    @Test
    func plainTextJoinsBlocksWithNewlines() {
        let document = MarkdownDocument("# Title\n\nBody text.\n\n- Item")

        #expect(document.plainText == "Title\nBody text.\nItem")
    }

    @Test
    func plainPreviewCollapsesMarkdownToASingleLine() {
        let preview = MarkdownDocument.plainPreview(
            of: "# Site Visit\n\nWalked the **north** wing.\n\n- Photograph it"
        )

        #expect(preview == "Site Visit Walked the north wing. Photograph it")
    }

    @Test
    func previewReadsOnlyTheOpeningOfALongBody() {
        let opening = "The stairwell lighting is still out."
        let body = opening + "\n\n" + String(repeating: "Filler paragraph. ", count: 400)

        let preview = MarkdownDocument.plainPreview(of: body)

        // The row shows two lines, so the preview stops well before the end of
        // a long note rather than parsing all of it.
        #expect(preview.hasPrefix(opening))
        #expect(preview.count < 500)
    }

    @Test
    func previewOfAShortBodyIsUnchangedByTheReadLimit() {
        let body = "# Site Visit\n\nWalked the **north** wing."

        #expect(
            MarkdownDocument.plainPreview(of: body) == "Site Visit Walked the north wing."
        )
    }

    @Test
    func previewOfEmptyBodyIsEmpty() {
        #expect(MarkdownDocument.plainPreview(of: "").isEmpty)
        #expect(MarkdownDocument.plainPreview(of: "   \n  ").isEmpty)
    }
}
