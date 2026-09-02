//
//  MarkdownSourceMapTests.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import Testing
@testable import CaseNotes

@MainActor
struct MarkdownSourceMapTests {
    /// Asserts the two invariants every division has to hold.
    ///
    /// A map that loses a character, leaves a gap, or disagrees with the parse
    /// would let live preview corrupt a note, so both are checked for every
    /// source these tests build rather than only for the interesting ones.
    ///
    /// - Parameter source: The body to divide.
    /// - Returns: The map, so a test can go on to assert on its regions.
    @discardableResult
    private func wellFormedMap(of source: String) -> MarkdownSourceMap {
        let map = MarkdownSourceMap(source)

        #expect(map.regions.map(map.text(of:)).joined() == source)

        var utf16Cursor = 0

        for region in map.regions {
            #expect(region.utf16Range.lowerBound == utf16Cursor)
            #expect(region.utf16Range.count == map.text(of: region).utf16.count)

            utf16Cursor = region.utf16Range.upperBound
        }

        #expect(utf16Cursor == source.utf16.count)
        #expect(map.regions.flatMap(\.blocks) == MarkdownDocument(source).blocks)
        #expect(map.regions.map(\.id) == Array(map.regions.indices))

        return map
    }

    /// The region a caret at a position falls in, by the text it owns.
    private func regionText(of source: String, at utf16Offset: Int) -> String? {
        MarkdownSourceMap(source)
            .region(containingUTF16Offset: utf16Offset)
            .map(MarkdownSourceMap(source).text(of:))
    }

    /// Where a substring starts, measured the way the map measures.
    private func utf16Offset(of fragment: String, in source: String) -> Int {
        guard let range = source.range(of: fragment) else {
            Issue.record("Fixture does not contain \(fragment)")
            return 0
        }

        return source.utf16.distance(from: source.utf16.startIndex, to: range.lowerBound.samePosition(in: source.utf16)!)
    }

    // MARK: Shape

    @Test
    func anEmptyBodyIsOneRegionACaretCanReach() {
        let map = wellFormedMap(of: "")

        #expect(map.regions.count == 1)
        #expect(map.regions[0].isEmpty)
        #expect(map.regions[0].utf16Range == 0..<0)
    }

    @Test
    func blocksSeparatedByBlankLinesBecomeSeparateRegions() {
        let source = "# Case Strategy\n\nThis is **important evidence**.\n\n## Documents\n"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)
        #expect(map.text(of: map.regions[0]) == "# Case Strategy\n\n")
        #expect(map.text(of: map.regions[1]) == "This is **important evidence**.\n\n")
        #expect(map.text(of: map.regions[2]) == "## Documents\n")
    }

    @Test
    func aRegionKeepsTheBlankLinesBelowIt() {
        let source = "Alpha\n\n\nBeta"
        let map = wellFormedMap(of: source)

        #expect(map.text(of: map.regions[0]) == "Alpha\n\n\n")
        #expect(map.text(of: map.regions[1]) == "Beta")
    }

    @Test
    func aTrailingRunOfBlankLinesStaysWithTheBlockAboveIt() {
        let source = "Alpha\n\n\n"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 1)
    }

    @Test
    func aBodyOfNothingButBlankLinesIsOneReachableRegion() {
        let map = wellFormedMap(of: "\n\n\n")

        #expect(map.regions.count == 1)
        #expect(map.regions[0].isEmpty)
    }

    // MARK: Activation by construct

    @Test
    func aCaretInAHeadingActivatesTheHeadingSource() {
        let source = "# Case Strategy\n\nBody text.\n"

        #expect(regionText(of: source, at: 3) == "# Case Strategy\n\n")
    }

    @Test
    func aCaretInAParagraphActivatesTheWholeParagraphIncludingItsSyntax() {
        let source = "# Case Strategy\n\nThis is **important evidence**.\n"
        let offset = utf16Offset(of: "important", in: source)

        #expect(regionText(of: source, at: offset) == "This is **important evidence**.\n")
    }

    @Test
    func aCaretInAListItemActivatesThatItemAlone() {
        let source = "- Review report\n- Check timeline\n"
        let offset = utf16Offset(of: "timeline", in: source)

        #expect(regionText(of: source, at: offset) == "- Check timeline\n")
        #expect(regionText(of: source, at: 2) == "- Review report\n")
    }

    @Test
    func anOrderedListKeepsItsOwnNumberInEachRegion() {
        let source = "1. one\n2. two\n3. three\n"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)

        let ordinals = map.regions.compactMap { region -> Int? in
            guard case let .listItem(ordinal, _, _) = region.blocks.first else {
                return nil
            }

            return ordinal
        }

        #expect(ordinals == [1, 2, 3])
    }

    @Test
    func aNestedListItemTravelsWithTheItemItSitsUnder() {
        // Parsed on its own, an indented item loses the depth its parent gives
        // it. The division has to keep the two together for that reason, and
        // the third item is still independent.
        let source = "- a\n  - b\n- c"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 2)
        #expect(map.text(of: map.regions[0]) == "- a\n  - b\n")
        #expect(map.text(of: map.regions[1]) == "- c")
    }

    @Test
    func aMultilineBlockQuoteActivatesWhole() {
        let source = "> alpha\n> beta\n\nAfter"
        let offset = utf16Offset(of: "beta", in: source)

        #expect(regionText(of: source, at: offset) == "> alpha\n> beta\n\n")
    }

    @Test
    func aQuoteContinuedLazilyOnTheNextLineActivatesWhole() {
        let source = "> alpha\nbeta\n\nAfter"

        #expect(regionText(of: source, at: utf16Offset(of: "beta", in: source)) == "> alpha\nbeta\n\n")
    }

    @Test
    func aFencedCodeBlockActivatesWholeEvenWithABlankLineInside() {
        let source = "Intro\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\nAfter"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)
        #expect(map.text(of: map.regions[1]) == "```swift\nlet a = 1\n\nlet b = 2\n```\n\n")
        #expect(regionText(of: source, at: utf16Offset(of: "let b", in: source)) == "```swift\nlet a = 1\n\nlet b = 2\n```\n\n")
    }

    @Test
    func aParagraphBrokenByHandActivatesAsOneRegion() {
        let source = "Milk\nBread\nCoffee\n\nAfter"

        #expect(regionText(of: source, at: utf16Offset(of: "Bread", in: source)) == "Milk\nBread\nCoffee\n\n")
    }

    @Test
    func indentedCodeSeparatedByABlankLineStaysOneRegion() {
        let source = "    alpha\n\n    beta"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 1)

        guard case .codeBlock = map.regions[0].blocks.first else {
            Issue.record("Expected indented code")
            return
        }
    }

    // MARK: Breaks and setext headings

    @Test
    func aThematicBreakIsItsOwnRegionAndNotBodyText() {
        let source = "One\n\n---\n\nTwo"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)
        #expect(map.regions[1].blocks == [.thematicBreak])
        #expect(map.text(of: map.regions[1]) == "---\n\n")

        // Its neighbours keep their own text, so activating a break never drags
        // a paragraph into it.
        #expect(map.text(of: map.regions[0]) == "One\n\n")
        #expect(map.text(of: map.regions[2]) == "Two")
    }

    @Test
    func everySpellingOfABreakDividesAlike() {
        for spelling in ["---", "***", "___", "- - -", "-----"] {
            let source = "One\n\n\(spelling)\n\nTwo"
            let map = wellFormedMap(of: source)

            #expect(map.regions.count == 3)
            #expect(map.regions[1].blocks == [.thematicBreak])
        }
    }

    @Test
    func dashesInsideFencedCodeAreCodeRatherThanABreak() {
        let source = "```\n---\n```\n\nAfter"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 2)
        #expect(!map.regions.contains { $0.blocks.contains(.thematicBreak) })
        #expect(map.text(of: map.regions[0]) == "```\n---\n```\n\n")
    }

    @Test
    func aSetextHeadingIsOneRegionRatherThanTextAboveABreak() {
        let source = "Heading\n---\n\nBody"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 2)
        #expect(map.text(of: map.regions[0]) == "Heading\n---\n\n")

        guard case let .heading(level, _) = map.regions[0].blocks.first else {
            Issue.record("Expected a setext heading")
            return
        }

        #expect(level == 2)

        // The caret anywhere in the heading, including on the dashes, edits the
        // heading rather than a break that is not there.
        #expect(regionText(of: source, at: utf16Offset(of: "---", in: source)) == "Heading\n---\n\n")
    }

    // MARK: Malformed source

    @Test
    func malformedMarkdownStaysCoveredAndEditable() {
        let source = "**unclosed *bold and [link](\n\nnext paragraph"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 2)
        #expect(map.text(of: map.regions[0]) == "**unclosed *bold and [link](\n\n")
    }

    @Test
    func anUnterminatedFenceStillDividesWithoutLosingText() {
        wellFormedMap(of: "```swift\nlet x = 1\n\nstill inside")
    }

    @Test
    func aTableLikeBodyStillCoversEveryCharacter() {
        wellFormedMap(of: "| a | b |\n| - | - |\n| 1 | 2 |")
    }

    @Test
    func aLinkReferenceDefinitionKeepsItsUserWithTheDefinition() {
        // The definition and the paragraph that uses it only parse alike
        // together, so validation refuses to cut between them rather than
        // rendering a resolved link as raw brackets.
        let source = "[handbook]: https://example.com\n\nSee the [handbook]."
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 1)
    }

    // MARK: Unicode

    @Test
    func emojiAndNonLatinTextDoNotBreakOffsets() {
        let source = "# Caf\u{00E9} \u{1F9EA}\n\nEvidence \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} logged.\n\n- \u{4E2D}\u{6587} note\n"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)

        // A UTF-16 offset taken from the middle of the second region has to
        // resolve to the second region, which it cannot if offsets were counted
        // in characters anywhere along the way.
        let offset = utf16Offset(of: "logged", in: source)

        #expect(regionText(of: source, at: offset) == "Evidence \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} logged.\n\n")
    }

    @Test
    func aRegionsSpanIsCountedInCodeUnitsRatherThanCharacters() {
        // The first region holds an emoji, which is one character and two code
        // units. A span counted in characters would put the second region two
        // units early and every offset after it would address the wrong text.
        let source = "\u{1F9EA} alpha\n\n\u{4E2D}\u{6587}\n"
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 2)
        #expect(map.text(of: map.regions[0]) == "\u{1F9EA} alpha\n\n")
        #expect(map.regions[0].utf16Range.count == 10)
        #expect(map.text(of: map.regions[0]).count == 9)
        #expect(map.regions[1].utf16Range.lowerBound == 10)
    }

    // MARK: Locating a region

    @Test
    func aCaretPastTheLastCharacterBelongsToTheLastRegion() {
        let source = "Alpha\n\nBeta"
        let map = MarkdownSourceMap(source)

        #expect(map.region(containingUTF16Offset: source.utf16.count)?.id == map.regions.count - 1)
    }

    @Test
    func regionIdentityAddressesTheSameRegionItWasTakenFrom() {
        let source = "Alpha\n\nBeta\n\nGamma"
        let map = MarkdownSourceMap(source)

        for region in map.regions {
            #expect(map.region(id: region.id) == region)
        }

        #expect(map.region(id: map.regions.count) == nil)
    }

    // MARK: Writing an edit back

    @Test
    func replacingARegionRewritesOnlyThatRegion() {
        let source = "# Case Strategy\n\nThis is **important evidence**.\n\n## Documents\n"
        let map = MarkdownSourceMap(source)
        let paragraph = map.regions[1]

        let edited = MarkdownSourceMap.replacing(
            source,
            utf16Range: paragraph.utf16Range,
            with: "This is *supporting* evidence.\n\n"
        )

        #expect(edited == "# Case Strategy\n\nThis is *supporting* evidence.\n\n## Documents\n")
    }

    @Test
    func replacingARegionThatHoldsEmojiKeepsTheCharactersAroundItIntact() {
        let source = "\u{1F9EA} alpha\n\nbeta\n"
        let map = MarkdownSourceMap(source)

        let edited = MarkdownSourceMap.replacing(
            source,
            utf16Range: map.regions[1].utf16Range,
            with: "gamma\n"
        )

        #expect(edited == "\u{1F9EA} alpha\n\ngamma\n")
    }

    @Test
    func aStaleSpanIsClampedRatherThanCrashing() {
        let source = "Alpha"

        #expect(MarkdownSourceMap.substring(of: source, utf16Range: 0..<500) == "Alpha")
        #expect(MarkdownSourceMap.substring(of: source, utf16Range: 400..<500) == "")
        #expect(MarkdownSourceMap.substring(of: source, utf16Range: -20..<2) == "Al")
        #expect(MarkdownSourceMap.replacing(source, utf16Range: 3..<500, with: "!") == "Alp!")
    }

    // MARK: Structure changing under an edit

    @Test
    func typingABlankLineSplitsOneRegionIntoTwoWithoutLosingText() {
        let before = "Alpha and beta.\n"
        let map = MarkdownSourceMap(before)

        // What live preview does when the region under the caret grows a
        // boundary: it writes the typed text back and divides again.
        let after = MarkdownSourceMap.replacing(
            before,
            utf16Range: map.regions[0].utf16Range,
            with: "Alpha.\n\nBeta.\n"
        )

        #expect(after == "Alpha.\n\nBeta.\n")

        let divided = wellFormedMap(of: after)

        #expect(divided.regions.count == 2)
        #expect(divided.text(of: divided.regions[1]) == "Beta.\n")
    }

    @Test
    func aParagraphTypedIntoAHeadingReclassifiesWithoutLosingText() {
        let before = "Alpha\n\nBeta\n"
        let map = MarkdownSourceMap(before)

        let after = MarkdownSourceMap.replacing(
            before,
            utf16Range: map.regions[0].utf16Range,
            with: "## Alpha\n\n"
        )

        #expect(after == "## Alpha\n\nBeta\n")

        let divided = wellFormedMap(of: after)

        guard case let .heading(level, _) = divided.regions[0].blocks.first else {
            Issue.record("Expected the region to have become a heading")
            return
        }

        #expect(level == 2)
    }

    @Test
    func joiningTwoRegionsLeavesOneParagraphAndEveryCharacter() {
        // Delete at the very start of a region takes the character above it,
        // which is how two blocks are joined when each region only holds its
        // own text.
        let before = "Alpha\n\nBeta"
        let map = MarkdownSourceMap(before)
        let start = map.regions[1].utf16Range.lowerBound

        let after = MarkdownSourceMap.replacing(before, utf16Range: (start - 1)..<start, with: "")

        #expect(after == "Alpha\nBeta")

        let divided = wellFormedMap(of: after)

        #expect(divided.regions.count == 1)
    }

    @Test
    func dividingIsStableAcrossRepeatedCallsForTheSameSource() {
        let source = "# One\n\nTwo\n\n- three\n- four\n\n> five\n"

        #expect(MarkdownSourceMap(source) == MarkdownSourceMap(source))
    }

    @Test
    func theCacheHandsBackTheSameDivisionUntilTheSourceChanges() {
        let cache = ParsedMarkdownSource()
        let first = cache.map(for: "# One\n\nTwo")

        #expect(cache.map(for: "# One\n\nTwo") == first)
        #expect(cache.map(for: "# One\n\nThree") != first)
    }

    // MARK: Repairing a division locally

    /// Rewrites one region and repairs the division the way live preview does
    /// on a keystroke, then reports both the repaired map and a whole-body
    /// division of the same text.
    private func repairing(
        _ source: String,
        region index: Int,
        to text: String
    ) -> (repaired: MarkdownSourceMap?, whole: MarkdownSourceMap, body: String) {
        let map = MarkdownSourceMap(source)
        let span = map.regions[index].utf16Range
        let body = MarkdownSourceMap.replacing(source, utf16Range: span, with: text)
        let edited = span.lowerBound..<(span.lowerBound + text.utf16.count)

        return (
            map.rebuilt(from: body, replacing: index..<(index + 1), covering: edited),
            MarkdownSourceMap(body),
            body
        )
    }

    @Test
    func repairingOneRegionMatchesDividingTheWholeBody() {
        // The fast path exists because dividing a whole note on every keystroke
        // cost text on a long one. It has to agree with the slow path for an
        // ordinary edit, which is what this checks across a split, a join into
        // one block, a change of block type, and an edit that changes nothing
        // structural.
        let source = "# Title\n\nAlpha paragraph.\n\n- one\n- two\n\nTail.\n"

        let cases: [(Int, String)] = [
            (1, "Alpha paragraph.\n\nBeta paragraph.\n\n"),
            (1, "## Alpha paragraph.\n\n"),
            (1, "Alpha paragraph, extended.\n\n"),
            (2, "- one\n- one and a half\n"),
            (0, "# Title\n\nSubtitle line.\n\n"),
            (4, "Tail, longer than it was.\n")
        ]

        for (index, text) in cases {
            let result = repairing(source, region: index, to: text)

            guard let repaired = result.repaired else {
                Issue.record("Repair refused for region \(index)")
                continue
            }

            #expect(repaired.source == result.body)
            #expect(repaired.regions.map(repaired.text(of:)).joined() == result.body)
            #expect(repaired.regions.map(\.utf16Range) == result.whole.regions.map(\.utf16Range))
            #expect(repaired.regions.flatMap(\.blocks) == result.whole.regions.flatMap(\.blocks))
            #expect(repaired.regions.map(\.id) == Array(repaired.regions.indices))
        }
    }

    @Test
    func repairingKeepsEveryCharacterEvenWhenTheEditIsLarge() {
        let source = "Alpha\n\nBeta\n\nGamma\n"
        let result = repairing(source, region: 1, to: "One\n\nTwo\n\nThree\n\nFour\n\n")

        guard let repaired = result.repaired else {
            Issue.record("Repair refused")
            return
        }

        #expect(result.body == "Alpha\n\nOne\n\nTwo\n\nThree\n\nFour\n\nGamma\n")
        #expect(repaired.regions.map(repaired.text(of:)).joined() == result.body)
        #expect(repaired.regions.count == 6)
    }

    @Test
    func repairingJoinsTwoRegionsThatHaveBecomeOneBlock() {
        // What a delete at the start of a region asks for: the two regions
        // either side of the deletion are re-divided together.
        let source = "Alpha\n\nBeta\n\nGamma\n"
        let map = MarkdownSourceMap(source)
        let start = map.regions[1].utf16Range.lowerBound
        let body = MarkdownSourceMap.replacing(source, utf16Range: (start - 1)..<start, with: "")
        let span = map.regions[0].utf16Range.lowerBound..<(map.regions[1].utf16Range.upperBound - 1)

        guard let repaired = map.rebuilt(from: body, replacing: 0..<2, covering: span) else {
            Issue.record("Repair refused")
            return
        }

        #expect(body == "Alpha\nBeta\n\nGamma\n")
        #expect(repaired.regions.count == 2)
        #expect(repaired.text(of: repaired.regions[0]) == "Alpha\nBeta\n\n")
        #expect(repaired.regions.map(repaired.text(of:)).joined() == body)
        #expect(repaired.regions.map(\.utf16Range) == MarkdownSourceMap(body).regions.map(\.utf16Range))
    }

    @Test
    func aRepairIsRefusedWhenItsArgumentsDoNotDescribeTheMap() {
        let map = MarkdownSourceMap("Alpha\n\nBeta\n")

        #expect(map.rebuilt(from: "Alpha\n\nBeta\n", replacing: 0..<0, covering: 0..<7) == nil)
        #expect(map.rebuilt(from: "Alpha\n\nBeta\n", replacing: 0..<9, covering: 0..<7) == nil)
        #expect(map.rebuilt(from: "Alpha\n\nBeta\n", replacing: 1..<2, covering: 0..<7) == nil)
    }

    @Test
    func aRepairedMapStillFindsTheRegionUnderTheCaret() {
        let source = "Alpha\n\nBeta\n"
        let result = repairing(source, region: 0, to: "Alpha.\n\nInserted.\n\n")

        guard let repaired = result.repaired else {
            Issue.record("Repair refused")
            return
        }

        let caret = result.body.utf16.count - 2

        #expect(repaired.region(containingUTF16Offset: caret)?.id == repaired.regions.count - 1)
        #expect(repaired.region(containingUTF16Offset: 0)?.id == 0)
    }

    // MARK: A realistic note

    @Test
    func aNoteUsingEverySupportedConstructDividesWithoutLosingAnything() {
        let source = """
            # Site Visit

            Walked the north wing with **facilities**. The stairwell lighting is \
            still out and the east door does not *latch*.

            ## Actions

            - Photograph the stairwell
            - Check the ramp handrail

            1. Raise a ticket
            2. Confirm the schedule

            > Parts are on order.

            ---

            ## Follow Up

            Use `notes.export()` or see the [handbook](https://example.com).

            ```swift
            let note = Note(title: "Site Visit")
            ```

            ---

            Confirm the schedule with the contractor.
            """

        let map = wellFormedMap(of: source)

        #expect(map.regions.count > 8)
        #expect(map.regions.filter { $0.blocks == [.thematicBreak] }.count == 2)

        // Every region can be entered, and entering one never changes the note.
        for region in map.regions {
            let rewritten = MarkdownSourceMap.replacing(
                source,
                utf16Range: region.utf16Range,
                with: map.text(of: region)
            )

            #expect(rewritten == source)
        }
    }

    @Test
    func aLongNoteDividesWithoutLosingAnything() {
        let source = (0..<80).map { index in
            switch index % 4 {
            case 0: "## Section \(index)"
            case 1: "Paragraph \(index) with **bold** and `code` in it."
            case 2: "- item \(index) one\n- item \(index) two"
            default: "> quoted line \(index)"
            }
        }
        .joined(separator: "\n\n")

        let map = wellFormedMap(of: source)

        #expect(map.regions.count > 80)
    }
}
