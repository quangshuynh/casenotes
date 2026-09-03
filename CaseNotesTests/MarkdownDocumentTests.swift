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
        case .thematicBreak, .attachment, nil:
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

    // MARK: Sections

    /// Convenience for asserting on a region's shape without inspecting text.
    private func shape(
        of sections: [MarkdownDocument.Section]
    ) -> [(id: Int, foldable: Bool, blocks: Int)] {
        sections.map { ($0.id, $0.precededByThematicBreak, $0.blocks.count) }
    }

    @Test
    func aBodyWithNoBreakIsOneRegionThatCannotBeFolded() {
        let document = MarkdownDocument("# Project\n\nOverview text.")

        #expect(document.sections.count == 1)
        #expect(document.sections[0].id == 0)
        #expect(document.sections[0].precededByThematicBreak == false)
        #expect(document.sections[0].blocks.count == 2)
    }

    @Test
    func anEmptyBodyHasNoRegions() {
        #expect(MarkdownDocument("").sections.isEmpty)
    }

    @Test
    func oneBreakLeavesTheOpeningVisibleAndMakesWhatFollowsFoldable() {
        let document = MarkdownDocument("Intro\n\n---\n\nSection A")

        #expect(shape(of: document.sections).map(\.foldable) == [false, true])
        #expect(text(of: document.sections[0].blocks.first) == "Intro")
        #expect(text(of: document.sections[1].blocks.first) == "Section A")
    }

    /// The rule the feature turns on: a divider owns what follows it and stops
    /// at the next divider, so folding one never takes the rest of the note.
    @Test
    func eachBreakOwnsOnlyTheContentUpToTheNextOne() {
        let document = MarkdownDocument(
            "Intro\n\n---\n\nSection A\n\nText A\n\n---\n\nSection B\n\nText B"
        )

        #expect(shape(of: document.sections).map(\.id) == [0, 1, 2])
        #expect(shape(of: document.sections).map(\.foldable) == [false, true, true])

        #expect(document.sections[1].blocks.map(text(of:)) == ["Section A", "Text A"])
        #expect(document.sections[2].blocks.map(text(of:)) == ["Section B", "Text B"])
    }

    @Test
    func aBodyThatOpensWithABreakGetsNoEmptyRegionAboveIt() {
        let document = MarkdownDocument("---\n\nSection A")

        #expect(document.sections.count == 1)
        #expect(document.sections[0].precededByThematicBreak)
        #expect(text(of: document.sections[0].blocks.first) == "Section A")
    }

    @Test
    func consecutiveBreaksProduceAnEmptyFoldableRegionBetweenThem() {
        let document = MarkdownDocument("A\n\n---\n\n---\n\nB")

        #expect(shape(of: document.sections).map(\.foldable) == [false, true, true])
        #expect(document.sections[1].blocks.isEmpty)
        #expect(text(of: document.sections[2].blocks.first) == "B")
    }

    @Test
    func aTrailingBreakEndsInAnEmptyRegionRatherThanBeingDropped() {
        let document = MarkdownDocument("A\n\n---")

        #expect(shape(of: document.sections).map(\.foldable) == [false, true])
        #expect(document.sections[1].blocks.isEmpty)
    }

    /// The correctness requirement behind parsing rather than splitting text: a
    /// rule inside a fence is code the user wrote, not a divider.
    @Test
    func dashesInsideAFencedCodeBlockAreNotARegionBoundary() {
        let document = MarkdownDocument("A\n\n```text\n---\n```\n\nB")

        #expect(document.sections.count == 1)
        #expect(document.sections[0].precededByThematicBreak == false)
        #expect(document.blocks.contains { block in
            if case let .codeBlock(_, code) = block { return code == "---" }
            return false
        })
    }

    @Test
    func dashesInsideAnIndentedCodeBlockAreNotARegionBoundary() {
        let document = MarkdownDocument("A\n\n    ---\n\nB")

        #expect(document.sections.count == 1)
    }

    /// `Heading` over dashes is a setext heading in Markdown, not a break, and
    /// splitting the source on a line of dashes would get this wrong.
    @Test
    func dashesUnderneathTextAreASetextHeadingRatherThanARegionBoundary() {
        let document = MarkdownDocument("Section A\n---\n\nBody")

        #expect(document.sections.count == 1)

        guard case let .heading(level, _) = document.blocks.first else {
            Issue.record("Expected a setext heading")
            return
        }

        #expect(level == 2)
    }

    /// Every spelling the parser accepts as a break divides alike, because the
    /// division reads the parsed block and never the characters.
    @Test
    func everyThematicBreakSpellingDividesTheSameWay() {
        for rule in ["---", "***", "___", "- - -", "-----"] {
            let document = MarkdownDocument("A\n\n\(rule)\n\nB")

            #expect(
                shape(of: document.sections).map(\.foldable) == [false, true],
                "\(rule) should divide the body"
            )
        }
    }

    @Test
    func structuredBlocksAroundABreakStayInTheRegionTheyBelongTo() {
        let document = MarkdownDocument(
            "# Project\n\n- Alpha\n\n---\n\n> Quoted\n\n```swift\nlet x = 1\n```"
        )

        #expect(document.sections.count == 2)

        guard case .heading = document.sections[0].blocks[0],
              case .listItem = document.sections[0].blocks[1],
              case .blockQuote = document.sections[1].blocks[0],
              case .codeBlock = document.sections[1].blocks[1]
        else {
            Issue.record("Expected the heading and list above the break, the quote and code below")
            return
        }
    }

    @Test
    func malformedMarkdownStillDividesWithoutCrashing() {
        let document = MarkdownDocument("**unclosed emphasis and [a broken](link")

        #expect(document.sections.count == 1)
        #expect(document.sections[0].precededByThematicBreak == false)
    }

    /// Folding may hide a region on screen, but it must never be able to lose
    /// text: every block that is not a divider belongs to exactly one region,
    /// in the order it was written.
    @Test
    func regionsCoverEveryBlockThatIsNotABreak() {
        let source = """
        # Project

        Overview text.

        ---

        Implementation notes.

        ---

        Testing notes.
        """
        let document = MarkdownDocument(source)

        let fromRegions = document.sections.flatMap(\.blocks)
        let fromBlocks = document.blocks.filter { $0 != .thematicBreak }

        #expect(fromRegions == fromBlocks)
    }

    /// Collapsed state is keyed by identity, so identity has to be the same
    /// answer every time for text that has not changed.
    @Test
    func regionIdentitiesAreStableForUnchangedSource() {
        let source = "Intro\n\n---\n\nSection A\n\n---\n\nSection B"

        #expect(MarkdownDocument(source).sections == MarkdownDocument(source).sections)
        #expect(MarkdownDocument(source).sections.map(\.id) == [0, 1, 2])
    }

    /// Dividing is presentation. The exporter reads the stored body, so a note
    /// that reads as several regions still leaves the app whole.
    @Test
    func dividingABodyDoesNotChangeWhatAnExportContains() {
        let body = "Intro\n\n---\n\nSection A\n\n---\n\nSection B"
        let note = Note(title: "Site Visit", body: body)

        _ = MarkdownDocument(note.body).sections

        #expect(note.body == body)
        #expect(
            NoteExport.markdown(for: note, includingAttribution: false)
                .contains(body)
        )
    }

    // MARK: Reuse

    /// The reading view keeps one of these across updates, so a stale answer
    /// would show the previous note's text under the current note's title.
    @Test
    func theCacheAlwaysAnswersForTheSourceItWasAsked() {
        let cache = ParsedMarkdown()

        #expect(cache.document(for: "# Site Visit") == MarkdownDocument("# Site Visit"))
        #expect(cache.document(for: "# Follow Up") == MarkdownDocument("# Follow Up"))
        #expect(cache.document(for: "# Site Visit") == MarkdownDocument("# Site Visit"))
    }

    @Test
    func repeatingTheSameSourceReturnsTheSameDocument() {
        let cache = ParsedMarkdown()
        let body = "Walked the north wing.\n\n- Photograph the stairwell"

        #expect(cache.document(for: body) == cache.document(for: body))
    }

    /// An empty body is the state a new note opens in, and it has to survive the
    /// cache starting out empty itself.
    @Test
    func anEmptySourceIsCachedAsHavingNoBlocks() {
        let cache = ParsedMarkdown()

        #expect(cache.document(for: "").blocks.isEmpty)
        #expect(cache.document(for: "Written later").blocks.count == 1)
        #expect(cache.document(for: "").blocks.isEmpty)
    }
}
