//
//  InlineAttachmentTests.swift
//  CaseNotesTests
//
//  Created by q on 9/3/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Placing a note's own files inside its Markdown.
///
/// The tests fall into four groups, matching the four things that have to hold
/// for the feature to be safe: a marker is recognized only where it really is a
/// block, the division and the parse agree about it, rewriting the body moves
/// nothing but the marker, and none of it changes what a save, a cancel, or a
/// deletion already did.
@MainActor
struct InlineAttachmentTests {
    private let first = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let second = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let editedAt = Date(timeIntervalSince1970: 1_700_009_000)

    /// The source text that places an attachment.
    private func marker(_ id: UUID) -> String {
        InlineAttachmentMarker.text(for: id)
    }

    /// Asserts a body divides into regions that rejoin exactly and agree with
    /// the parse, which are the two invariants every division has to hold.
    ///
    /// - Parameter source: The body to divide.
    /// - Returns: The map, so a test can go on to assert on its regions.
    @discardableResult
    private func wellFormedMap(of source: String) -> MarkdownSourceMap {
        let map = MarkdownSourceMap(source)

        #expect(map.regions.map(map.text(of:)).joined() == source)
        #expect(map.regions.flatMap(\.blocks) == MarkdownDocument(source).blocks)

        return map
    }

    // MARK: Marker syntax

    @Test
    func aMarkerIsWrittenAndReadBackAsTheSameIdentity() {
        let text = marker(first)

        #expect(text == "{{attachment:\(first.uuidString)}}")
        #expect(InlineAttachmentMarker.identifier(ofLine: text[...]) == first)
    }

    @Test
    func aMarkerIsRecognizedThroughIndentationAndItsOwnLineEnding() {
        #expect(InlineAttachmentMarker.identifier(ofLine: "  \(marker(first))"[...]) == first)
        #expect(InlineAttachmentMarker.identifier(ofLine: "\(marker(first))  \n"[...]) == first)
        #expect(InlineAttachmentMarker.identifier(ofLine: "\t\(marker(first))\n"[...]) == first)
    }

    @Test(arguments: [
        "`{{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}}`",
        "\\{{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}}",
        "See {{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}}",
        "{{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}} and more",
        "{{attachment:not-a-uuid}}",
        "{{attachment:}}",
        "{{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}",
        "- {{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}}",
        "> {{attachment:3F2504E0-4F89-11D3-9A0C-0305E82C3301}}",
    ])
    func aLineHoldingAnythingElseIsNotAMarker(line: String) {
        #expect(InlineAttachmentMarker.identifier(ofLine: line[...]) == nil)
    }

    @Test
    func aBodyWithNoMarkerTextIsNotScanned() {
        #expect(!InlineAttachmentMarker.mayAppear(in: "# Site Visit\n\nWalked the wing."))
        #expect(InlineAttachmentMarker.mayAppear(in: "before {{attachment: after"))
        #expect(InlineAttachmentMarker.candidateLines(in: "# Site Visit").isEmpty)
    }

    @Test
    func candidateLinesCoverTheWholeLineIncludingItsTerminator() {
        let source = "First.\n\n\(marker(first))\n\nSecond."
        let candidates = InlineAttachmentMarker.candidateLines(in: source)

        #expect(candidates.count == 1)
        #expect(candidates[0].id == first)
        #expect(String(source[candidates[0].range]) == "\(marker(first))\n")
    }

    // MARK: Detection in the parse

    @Test
    func aMarkerOnItsOwnBecomesAnAttachmentBlock() {
        #expect(MarkdownDocument(marker(first)).blocks == [.attachment(id: first)])
    }

    @Test
    func aMarkerBetweenTwoParagraphsBecomesABlockBetweenThem() {
        let document = MarkdownDocument("First.\n\n\(marker(first))\n\nSecond.")

        #expect(document.blocks.count == 3)
        #expect(document.blocks[1] == .attachment(id: first))
    }

    @Test
    func markersAtTheStartAndTheEndOfABodyBothResolve() {
        let opening = MarkdownDocument("\(marker(first))\n\nWalked the wing.")
        let closing = MarkdownDocument("Walked the wing.\n\n\(marker(first))")

        #expect(opening.blocks.first == .attachment(id: first))
        #expect(closing.blocks.last == .attachment(id: first))
    }

    @Test
    func twoMarkersSeparatedByABlankLineBothResolve() {
        let document = MarkdownDocument("\(marker(first))\n\n\(marker(second))")

        #expect(document.blocks == [.attachment(id: first), .attachment(id: second)])
    }

    @Test
    func thesameAttachmentPlacedTwiceIsTwoBlocks() {
        let document = MarkdownDocument("\(marker(first))\n\nNotes.\n\n\(marker(first))")

        #expect(document.blocks.count == 3)
        #expect(document.blocks[0] == .attachment(id: first))
        #expect(document.blocks[2] == .attachment(id: first))
    }

    @Test
    func aMarkerResolvesAgainstEveryNeighbouringConstruct() {
        let source = """
            # Site Visit

            \(marker(first))

            Walked the north wing.

            \(marker(second))

            - Photograph the stairwell
            - Check the handrail

            > Parts are on order.

            \(marker(first))

            ---

            \(marker(second))
            """

        let blocks = MarkdownDocument(source).blocks

        #expect(blocks.filter { $0 == .attachment(id: first) }.count == 2)
        #expect(blocks.filter { $0 == .attachment(id: second) }.count == 2)
        #expect(blocks.contains(.thematicBreak))
        wellFormedMap(of: source)
    }

    @Test
    func aMarkerUnderAHeadingWithNoBlankLineIsStillItsOwnBlock() {
        let document = MarkdownDocument("# Site Visit\n\(marker(first))")

        #expect(document.blocks.count == 2)
        #expect(document.blocks[1] == .attachment(id: first))
    }

    @Test
    func aMarkerUnderASetextHeadingResolves() {
        let document = MarkdownDocument("Site Visit\n---\n\n\(marker(first))")

        #expect(document.blocks.count == 2)
        #expect(document.blocks[1] == .attachment(id: first))

        guard case let .heading(level, _) = document.blocks[0] else {
            Issue.record("Expected a setext heading")
            return
        }

        #expect(level == 2)
    }

    @Test
    func aMarkerAboveAListResolvesAndTheListStaysAList() {
        let document = MarkdownDocument("\(marker(first))\n- Photograph the stairwell")

        #expect(document.blocks.count == 2)
        #expect(document.blocks[0] == .attachment(id: first))

        guard case .listItem = document.blocks[1] else {
            Issue.record("Expected a list item")
            return
        }
    }

    @Test
    func aMarkerInAFencedBlockStaysCode() {
        let source = "```\n\(marker(first))\n```"
        let document = MarkdownDocument(source)

        #expect(document.blocks.count == 1)
        #expect(!document.blocks.contains(.attachment(id: first)))

        guard case let .codeBlock(_, code) = document.blocks[0] else {
            Issue.record("Expected a code block")
            return
        }

        #expect(code == marker(first))
        wellFormedMap(of: source)
    }

    @Test
    func aRealPlacementSurvivesAMarkerWrittenInsideAFence() {
        let source = "\(marker(first))\n\n```\n\(marker(second))\n```"
        let blocks = MarkdownDocument(source).blocks

        #expect(blocks.count == 2)
        #expect(blocks[0] == .attachment(id: first))
        #expect(!blocks.contains(.attachment(id: second)))
        wellFormedMap(of: source)
    }

    @Test
    func aMarkerInAnIndentedCodeBlockStaysCode() {
        let document = MarkdownDocument("    \(marker(first))")

        #expect(document.blocks.count == 1)
        #expect(!document.blocks.contains(.attachment(id: first)))

        guard case .codeBlock = document.blocks[0] else {
            Issue.record("Expected a code block")
            return
        }
    }

    @Test
    func aMarkerInInlineCodeStaysAParagraph() {
        let document = MarkdownDocument("`\(marker(first))`")

        #expect(document.blocks.count == 1)
        #expect(!document.blocks.contains(.attachment(id: first)))
    }

    @Test
    func anEscapedMarkerStaysAParagraph() {
        let document = MarkdownDocument("\\\(marker(first))")

        #expect(document.blocks.count == 1)
        #expect(!document.blocks.contains(.attachment(id: first)))
    }

    @Test
    func aMarkerContinuingAParagraphStaysPartOfIt() {
        let document = MarkdownDocument("Walked the wing.\n\(marker(first))")

        #expect(document.blocks.count == 1)
        #expect(!document.blocks.contains(.attachment(id: first)))
    }

    @Test
    func aMarkerInsideAListItemOrAQuoteStaysThere() {
        let list = MarkdownDocument("- \(marker(first))")
        let quote = MarkdownDocument("> \(marker(first))")

        #expect(!list.blocks.contains(.attachment(id: first)))
        #expect(!quote.blocks.contains(.attachment(id: first)))

        guard case .listItem = list.blocks[0], case .blockQuote = quote.blocks[0] else {
            Issue.record("Expected the surrounding construct to survive")
            return
        }
    }

    @Test
    func anUnknownIdentifierIsNotAPlacement() {
        let document = MarkdownDocument("{{attachment:site-plan.pdf}}")

        #expect(document.blocks.count == 1)

        guard case .paragraph = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
    }

    @Test
    func aMarkerSurvivesEmojiAndMalformedMarkdownAroundIt() {
        let source = "Hello 👋🏽 **unclosed\n\n\(marker(first))\n\n👋🏽"
        let document = MarkdownDocument(source)

        #expect(document.blocks.contains(.attachment(id: first)))
        wellFormedMap(of: source)
    }

    @Test
    func placementsAreLeftOutOfPlainTextAndListPreviews() {
        let source = "\(marker(first))\n\nWalked the north wing."

        #expect(MarkdownDocument(source).plainText == "Walked the north wing.")
        #expect(MarkdownDocument.plainPreview(of: source) == "Walked the north wing.")
    }

    // MARK: Regions

    @Test
    func aPlacementOwnsARegionOfItsOwn() {
        let source = "First.\n\n\(marker(first))\n\nSecond."
        let map = wellFormedMap(of: source)

        #expect(map.regions.count == 3)
        #expect(map.text(of: map.regions[1]) == "\(marker(first))\n\n")
        #expect(InlineAttachments.attachmentID(of: map.regions[1]) == first)
        #expect(InlineAttachments.attachmentID(of: map.regions[0]) == nil)
    }

    @Test
    func placementsAreListedInReadingOrderWithTheirSpans() {
        let source = "First.\n\n\(marker(first))\n\nSecond.\n\n\(marker(second))"
        let map = MarkdownSourceMap(source)
        let placements = InlineAttachments.placements(in: map)

        #expect(placements.count == 2)
        #expect(placements.map(\.attachmentID) == [first, second])
        #expect(placements.map(\.id) == [1, 3])
        #expect(placements[0].utf16Range == map.regions[1].utf16Range)
        #expect(placements[1].utf16Range == map.regions[3].utf16Range)
    }

    @Test
    func aLongNoteWithSeveralPlacementsStillDividesWell() {
        var source = ""

        for index in 0..<40 {
            source += "Paragraph number \(index) with a little more text after it.\n\n"
            source += index.isMultiple(of: 4) ? "\(marker(first))\n\n" : ""
        }

        let map = wellFormedMap(of: source)

        #expect(InlineAttachments.placements(in: map).count == 10)
    }

    // MARK: Insertion

    @Test
    func insertingIntoAnEmptyBodyWritesTheMarkerAndNothingElse() {
        let insertion = InlineAttachments.inserting(first, into: "", atUTF16Offset: 0)

        #expect(insertion.source == marker(first))
        #expect(insertion.markerUTF16Range == 0..<marker(first).utf16.count)
        #expect(insertion.caretUTF16Offset == marker(first).utf16.count)
        #expect(MarkdownDocument(insertion.source).blocks == [.attachment(id: first)])
    }

    @Test
    func insertingAtTheStartPutsThePlacementAboveTheOpeningBlock() {
        let insertion = InlineAttachments.inserting(
            first,
            into: "Walked the north wing.",
            atUTF16Offset: 0
        )

        #expect(insertion.source == "\(marker(first))\n\nWalked the north wing.")
    }

    @Test
    func insertingAtTheEndPutsThePlacementBelowEverything() {
        let body = "Walked the north wing."
        let insertion = InlineAttachments.inserting(
            first,
            into: body,
            atUTF16Offset: body.utf16.count
        )

        #expect(insertion.source == "Walked the north wing.\n\n\(marker(first))")
    }

    @Test
    func insertingFromInsideABlockLandsAfterThatBlockRatherThanInsideIt() {
        let insertion = InlineAttachments.inserting(
            first,
            into: "First.\n\nSecond.",
            atUTF16Offset: 3
        )

        #expect(insertion.source == "First.\n\n\(marker(first))\n\nSecond.")
    }

    @Test
    func insertingFromTheStartOfALaterBlockLandsAboveIt() {
        let insertion = InlineAttachments.inserting(
            first,
            into: "First.\n\nSecond.",
            atUTF16Offset: 8
        )

        #expect(insertion.source == "First.\n\n\(marker(first))\n\nSecond.")
    }

    @Test
    func insertingFromInsideAFencedBlockDoesNotBreakTheFence() {
        let body = "```\nlet note = Note()\n```"
        let insertion = InlineAttachments.inserting(first, into: body, atUTF16Offset: 8)

        #expect(insertion.source == "\(body)\n\n\(marker(first))")

        let blocks = MarkdownDocument(insertion.source).blocks

        #expect(blocks.count == 2)
        #expect(blocks[1] == .attachment(id: first))
    }

    @Test
    func insertingAroundUnicodeMeasuresInTheSameUnitsTheEditorDoes() {
        let body = "Hello 👋🏽 world"
        let insertion = InlineAttachments.inserting(
            first,
            into: body,
            atUTF16Offset: body.utf16.count
        )

        #expect(insertion.source == "\(body)\n\n\(marker(first))")
        #expect(insertion.markerUTF16Range.lowerBound == body.utf16.count + 2)

        let placements = InlineAttachments.placements(in: insertion.source)

        #expect(placements.count == 1)
        #expect(placements[0].utf16Range.lowerBound == insertion.markerUTF16Range.lowerBound)
    }

    @Test
    func insertingAgainstAnExistingBlankLineAddsNoSecondOne() {
        let insertion = InlineAttachments.inserting(
            first,
            into: "First.\n\nSecond.",
            atUTF16Offset: 6
        )

        #expect(insertion.source == "First.\n\n\(marker(first))\n\nSecond.")
        #expect(!insertion.source.contains("\n\n\n"))
    }

    @Test
    func insertingLeavesEveryOtherCharacterAlone() {
        let body = "# Site Visit\n\n> Parts are on order.\n\n```\n- not a list\n```\n"
        let insertion = InlineAttachments.inserting(
            first,
            into: body,
            atUTF16Offset: body.utf16.count
        )

        // Only the separator the marker needs is added: the body already ended
        // with one newline, so it gains the second and nothing else.
        #expect(insertion.source == "\(body)\n\(marker(first))")
        #expect(insertion.source.hasPrefix(body))
    }

    @Test
    func placingAndLiftingAPlacementLeavesTheWritingItself() {
        let bodies = [
            "",
            "Walked the north wing.",
            "First.\n\nSecond.",
            "# Site Visit\n\n> Parts are on order.\n",
            "Hello 👋🏽 world",
        ]

        for body in bodies {
            for offset in [0, body.utf16.count] {
                let insertion = InlineAttachments.inserting(first, into: body, atUTF16Offset: offset)
                let placement = InlineAttachments.placements(in: insertion.source).first
                let removed = InlineAttachments.removing(placement: placement?.id ?? 0, in: insertion.source)

                #expect(placement != nil)
                #expect(removed?.contains(InlineAttachmentMarker.prefix) == false)

                // A separator that was above the marker stays where it was, so
                // a placement at the end of a note leaves a trailing blank line
                // behind it. Nothing the author wrote changes.
                #expect(
                    removed?.trimmingCharacters(in: .newlines)
                        == body.trimmingCharacters(in: .newlines)
                )
            }
        }
    }

    // MARK: Movement

    private var threeBlocks: String {
        "First.\n\n\(marker(first))\n\nSecond."
    }

    @Test
    func movingAPlacementUpSwapsItWithTheBlockAbove() {
        let moved = InlineAttachments.moving(placement: 1, .up, in: threeBlocks)

        #expect(moved?.source == "\(marker(first))\n\nFirst.\n\nSecond.")
    }

    @Test
    func movingAPlacementDownSwapsItWithTheBlockBelow() {
        let moved = InlineAttachments.moving(placement: 1, .down, in: threeBlocks)

        #expect(moved?.source == "First.\n\nSecond.\n\n\(marker(first))")
    }

    @Test
    func movingChangesNothingButThePlacement() {
        let up = InlineAttachments.moving(placement: 1, .up, in: threeBlocks)
        let down = InlineAttachments.moving(placement: 1, .down, in: threeBlocks)

        for source in [up?.source, down?.source] {
            let stripped = try? #require(source)
                .replacingOccurrences(of: marker(first), with: "")
                .replacingOccurrences(of: "\n\n\n", with: "\n\n")
                .trimmingCharacters(in: .newlines)

            #expect(stripped == "First.\n\nSecond.")
        }
    }

    @Test
    func movingPastTheEndOfTheDocumentIsRefused() {
        let atTop = "\(marker(first))\n\nFirst."
        let atBottom = "First.\n\n\(marker(first))"

        #expect(InlineAttachments.moving(placement: 0, .up, in: atTop) == nil)
        #expect(InlineAttachments.moving(placement: 1, .down, in: atBottom) == nil)
    }

    @Test
    func movingARegionThatIsNotAPlacementIsRefused() {
        #expect(InlineAttachments.moving(placement: 0, .down, in: threeBlocks) == nil)
        #expect(InlineAttachments.moving(placement: 9, .up, in: threeBlocks) == nil)
        #expect(InlineAttachments.removing(placement: 0, in: threeBlocks) == nil)
    }

    @Test
    func aPlacementCanBeWalkedThroughSeveralBlocksAndBack() {
        var source = "\(marker(first))\n\nOne.\n\nTwo.\n\nThree."

        for _ in 0..<3 {
            let placement = try? #require(InlineAttachments.placements(in: source).first)
            source = try! #require(
                InlineAttachments.moving(placement: placement!.id, .down, in: source)
            ).source
        }

        #expect(source == "One.\n\nTwo.\n\nThree.\n\n\(marker(first))")

        for _ in 0..<3 {
            let placement = try? #require(InlineAttachments.placements(in: source).first)
            source = try! #require(
                InlineAttachments.moving(placement: placement!.id, .up, in: source)
            ).source
        }

        // The blank line the marker left the end of the note with stays there,
        // because it belonged to the paragraph above rather than to the marker.
        #expect(source == "\(marker(first))\n\nOne.\n\nTwo.\n\nThree.\n\n")
    }

    @Test
    func movingKeepsTheMarkerParsingAsAPlacement() {
        let moved = InlineAttachments.moving(placement: 1, .up, in: "# Heading\n\n\(marker(first))\n\nProse.")

        #expect(MarkdownDocument(moved?.source ?? "").blocks.first == .attachment(id: first))
    }

    // MARK: Removing a placement

    @Test
    func removingAPlacementTakesOutTheMarkerAndNothingElse() {
        let removed = InlineAttachments.removing(placement: 1, in: threeBlocks)

        #expect(removed == "First.\n\nSecond.")
    }

    @Test
    func removingAPlacementThatEndsTheNoteLeavesItsSeparatorInPlace() {
        let removed = InlineAttachments.removing(
            placement: 1,
            in: "Walked the north wing.\n\n\(marker(first))"
        )

        // The blank line was above the marker, so it belonged to the paragraph
        // rather than travelling with the placement.
        #expect(removed == "Walked the north wing.\n\n")
    }

    @Test
    func removingOnePlacementLeavesTheOtherAlone() {
        let source = "\(marker(first))\n\nProse.\n\n\(marker(first))"
        let removed = InlineAttachments.removing(placement: 0, in: source)

        #expect(removed == "Prose.\n\n\(marker(first))")

        #expect(InlineAttachments.placements(in: removed ?? "").count == 1)
    }

    // MARK: Resolution

    /// A context, a file store, and the directory both are thrown away with.
    private struct Fixture {
        let context: ModelContext
        let root: URL
        let store: AttachmentStore

        init() throws {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
                NoteAttachment.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)

            root = URL.temporaryDirectory
                .appending(path: "casenotes-inline-attachments-\(UUID().uuidString)")
            store = AttachmentStore(
                containerDirectory: root.appending(path: "container"),
                stagingParentDirectory: root.appending(path: "staging")
            )
        }

        /// Stages a synthetic document as though the user had imported one.
        ///
        /// - Parameter name: The file name the attachment carries.
        /// - Returns: The staged file, ready to put in a draft.
        func stage(_ name: String) throws -> StagedAttachment {
            let directory = root.appending(path: "sources")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let url = directory.appending(path: name)
            try? FileManager.default.removeItem(at: url)
            try Data(repeating: 0x41, count: 96).write(to: url)

            return try store.stage(contentsOf: url)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test
    func aStagedFileResolvesBeforeItHasEverBeenSaved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let staged = try fixture.stage("brief.txt")
        let source = InlineAttachmentSource(
            draftAttachments: [DraftAttachment(staged: staged)],
            store: fixture.store
        )

        let resolved = try #require(source.attachment(for: staged.id))

        #expect(resolved.descriptor.originalFilename == "brief.txt")
        #expect(resolved.url == staged.url)
        #expect(!resolved.isImage)
    }

    @Test
    func aSavedFileResolvesToItsPlaceInTheStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = Note(title: "Site Visit", createdAt: createdAt, updatedAt: createdAt)
        fixture.context.insert(note)

        let staged = try fixture.stage("brief.txt")
        NoteAttachments.apply(
            [DraftAttachment(staged: staged)],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        let source = InlineAttachmentSource(
            attachments: [attachment],
            store: fixture.store
        )

        // Identity survives the move out of staging, which is what keeps a
        // marker written before the save pointing at the same file afterwards.
        #expect(attachment.id == staged.id)
        #expect(source.attachment(for: staged.id)?.url != nil)
    }

    @Test
    func aFileWhoseBytesHaveGoneResolvesWithNoURL() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = Note(title: "Site Visit", createdAt: createdAt, updatedAt: createdAt)
        fixture.context.insert(note)

        let staged = try fixture.stage("brief.txt")
        NoteAttachments.apply(
            [DraftAttachment(staged: staged)],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        fixture.store.removeStoredFile(named: attachment.storedFilename)

        let source = InlineAttachmentSource(
            attachments: [attachment],
            store: fixture.store
        )
        let resolved = try #require(source.attachment(for: attachment.id))

        #expect(resolved.url == nil)
        #expect(resolved.descriptor.originalFilename == "brief.txt")
    }

    @Test
    func anIdentityTheNoteNoLongerHoldsResolvesToNothing() {
        #expect(InlineAttachmentSource.unavailable.attachment(for: first) == nil)
        #expect(
            InlineAttachmentSource(attachments: []).attachment(for: first) == nil
        )
    }

    @Test
    func onlyAnImageTypeIsDrawnInTheNote() {
        let image = ResolvedInlineAttachment(
            id: first,
            descriptor: AttachmentDescriptor(
                originalFilename: "wing.png",
                contentTypeIdentifier: "public.png",
                byteCount: 2_048
            ),
            url: URL(filePath: "/tmp/wing.png")
        )

        let document = ResolvedInlineAttachment(
            id: second,
            descriptor: AttachmentDescriptor(
                originalFilename: "site-plan.pdf",
                contentTypeIdentifier: "com.adobe.pdf",
                byteCount: 2_048
            ),
            url: URL(filePath: "/tmp/site-plan.pdf")
        )

        #expect(image.isImage)
        #expect(!document.isImage)
    }

    @Test
    func aRenamedFileKeepsItsPlacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = Note(title: "Site Visit", createdAt: createdAt, updatedAt: createdAt)
        fixture.context.insert(note)

        let staged = try fixture.stage("brief.txt")
        NoteAttachments.apply(
            [DraftAttachment(staged: staged)],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        attachment.originalFilename = "renamed.txt"

        let source = InlineAttachmentSource(
            attachments: [attachment],
            store: fixture.store
        )

        #expect(source.attachment(for: staged.id)?.url != nil)
        #expect(source.attachment(for: staged.id)?.descriptor.originalFilename == "renamed.txt")
    }

    // MARK: Draft, history, and timestamps

    private func makeNote(in fixture: Fixture, body: String) -> Note {
        let note = Note(
            title: "Site Visit",
            body: body,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        fixture.context.insert(note)

        return note
    }

    @Test
    func placingAFileIsAnOrdinaryBodyEditForHistoryAndTimestamps() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: "Walked the north wing.")
        var draft = NoteDraft(note: note)

        draft.body = InlineAttachments.inserting(
            first,
            into: draft.body,
            atUTF16Offset: draft.body.utf16.count
        ).source

        let changed = NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt)
        let revisions = NoteHistory.revisions(of: note)

        #expect(changed)
        #expect(note.updatedAt == editedAt)
        #expect(note.body == "Walked the north wing.\n\n\(marker(first))")
        #expect(revisions.count == 1)
        #expect(revisions[0].body == "Walked the north wing.")
    }

    @Test
    func cancellingAfterPlacingLeavesTheStoredBodyExactlyAsItWas() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: "Walked the north wing.")
        var draft = NoteDraft(note: note)

        draft.body = InlineAttachments.inserting(first, into: draft.body, atUTF16Offset: 0).source

        #expect(draft != NoteDraft(note: note))

        // Cancel drops the draft rather than applying it.
        #expect(note.body == "Walked the north wing.")
        #expect(note.updatedAt == createdAt)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func cancellingAfterMovingLeavesTheStoredBodyExactlyAsItWas() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: threeBlocks)
        var draft = NoteDraft(note: note)

        draft.body = try #require(
            InlineAttachments.moving(placement: 1, .down, in: draft.body)
        ).source

        #expect(draft.body != note.body)
        #expect(note.body == threeBlocks)
        #expect(note.updatedAt == createdAt)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func placingAndThenRemovingAPlacementIsANoOpSave() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: "Walked the north wing.")
        var draft = NoteDraft(note: note)

        draft.body = InlineAttachments.inserting(
            first,
            into: draft.body,
            atUTF16Offset: draft.body.utf16.count
        ).source

        let placement = try #require(InlineAttachments.placements(in: draft.body).first)
        draft.body = try #require(
            InlineAttachments.removing(placement: placement.id, in: draft.body)
        )
        .trimmingCharacters(in: .newlines)

        #expect(draft.body == "Walked the north wing.")
        #expect(!NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt))
        #expect(note.updatedAt == createdAt)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func aNewNoteSavesItsPlacementAndItsFileTogether() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let staged = try fixture.stage("brief.txt")
        var draft = NoteDraft(title: "Site Visit")
        draft.attachments = [DraftAttachment(staged: staged)]
        draft.body = InlineAttachments.inserting(staged.id, into: "", atUTF16Offset: 0).source

        let note = draft.insertNote(
            into: fixture.context,
            at: createdAt,
            using: fixture.store
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        let placements = InlineAttachments.placements(in: note.body)

        #expect(placements.count == 1)
        #expect(placements[0].attachmentID == attachment.id)
        #expect(fixture.store.storedFileExists(named: attachment.storedFilename))
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func removingTheFileLeavesTheMarkerAndTheRestOfTheNoteIntact() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: "Walked the north wing.")
        let staged = try fixture.stage("brief.txt")

        NoteAttachments.apply(
            [DraftAttachment(staged: staged)],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        var draft = NoteDraft(note: note)
        draft.body = InlineAttachments.inserting(
            staged.id,
            into: draft.body,
            atUTF16Offset: draft.body.utf16.count
        ).source

        NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt)
        NoteAttachments.apply(draft.attachments, to: note, in: fixture.context, using: fixture.store, at: editedAt)

        // Now delete the underlying file, which is a separate and deliberate
        // action from taking the placement out of the writing.
        var afterDeletion = NoteDraft(note: note)
        afterDeletion.attachments = []
        NoteAttachments.apply(
            afterDeletion.attachments,
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        let placements = InlineAttachments.placements(in: note.body)
        let source = InlineAttachmentSource(
            attachments: NoteAttachments.attachments(of: note),
            store: fixture.store
        )

        #expect(note.attachments.isEmpty)
        #expect(placements.count == 1)
        #expect(placements[0].attachmentID == staged.id)
        #expect(source.attachment(for: staged.id) == nil)
        #expect(note.body.contains("Walked the north wing."))
    }

    @Test
    func aCancelledEditNeitherKeepsTheStagedFileNorThePlacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: "Walked the north wing.")
        let staged = try fixture.stage("brief.txt")

        var draft = NoteDraft(note: note)
        draft.attachments = [DraftAttachment(staged: staged)]
        draft.body = InlineAttachments.inserting(
            staged.id,
            into: draft.body,
            atUTF16Offset: draft.body.utf16.count
        ).source

        NoteAttachments.discardStaged(draft.attachments, using: fixture.store)

        #expect(!FileManager.default.fileExists(atPath: staged.url.path(percentEncoded: false)))
        #expect(note.body == "Walked the north wing.")
        #expect(note.attachments.isEmpty)
    }

    // MARK: Export

    @Test
    func markdownExportCarriesEveryMarkerVerbatim() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, body: threeBlocks)

        let markdown = NoteExport.markdown(
            for: note,
            includingAttribution: false,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!
        )

        #expect(markdown.contains(marker(first)))
        #expect(markdown.contains(threeBlocks))
    }
}
