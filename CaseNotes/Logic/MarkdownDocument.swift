//
//  MarkdownDocument.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation

/// A note body parsed into renderable Markdown blocks.
///
/// Foundation's `AttributedString` Markdown parser records block structure as
/// `PresentationIntent` attributes but does not render it, and SwiftUI's `Text`
/// only honours inline styling. This type therefore does the one piece the
/// platform leaves out: it groups the parsed runs back into blocks so the view
/// layer can lay out headings, lists, quotes, and code.
///
/// The source string is never rewritten. It stays the note's stored form, and
/// parsing happens on the way to the screen.
struct MarkdownDocument: Equatable {
    /// A single top-level piece of a note body.
    ///
    /// Inline styling such as bold, italic, inline code, and links stays on the
    /// `AttributedString` payload and is applied by the renderer.
    enum Block: Equatable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        /// - Parameters:
        ///   - ordinal: The item number for ordered lists, `nil` for bulleted lists.
        ///   - depth: Nesting level, starting at zero for a top-level list.
        case listItem(ordinal: Int?, depth: Int, text: AttributedString)
        case blockQuote(AttributedString)
        case codeBlock(language: String?, code: String)
        case thematicBreak

        /// One of the note's own files, placed in the body by identity.
        ///
        /// The block carries the attachment's identity and nothing else. What
        /// the file is called, what kind of file it is, and whether its bytes
        /// are still there are answered where a block becomes pixels, so a
        /// rename never reaches the parse and a missing file never costs the
        /// note the rest of its structure. See ``InlineAttachmentMarker``.
        case attachment(id: UUID)
    }

    /// One region of a note body, as read mode divides it.
    ///
    /// A thematic break already reads as a divider between parts of a document,
    /// so read mode treats it as the head of a region rather than as decoration.
    /// A region owns the blocks after its break and stops at the next break,
    /// which is what keeps folding local: collapsing one divider never swallows
    /// the rest of the note.
    ///
    /// The blocks before the first break belong to a region of their own that no
    /// divider introduces, so nothing is invented above a note's opening.
    struct Section: Equatable, Identifiable {
        /// The region's place in the parsed order, counted from zero.
        ///
        /// Identity is position rather than content, so two regions that happen
        /// to read alike stay distinct and a collapsed one keeps its identity
        /// for as long as the source is unchanged.
        let id: Int

        /// Whether a thematic break introduces this region.
        ///
        /// False only for a note's opening region. A region that is introduced
        /// by a break but holds no blocks is the natural reading of two breaks
        /// in a row, and is still a region so the authored dividers all render.
        let precededByThematicBreak: Bool

        /// The blocks the region holds, without the break that introduces it.
        let blocks: [Block]
    }

    let blocks: [Block]

    /// The document divided at its thematic breaks.
    ///
    /// Computed with the parse rather than on demand, because the reading view
    /// asks for it on every update and folding a region must not cost a
    /// re-division of the document.
    let sections: [Section]

    /// Parses a Markdown source string.
    ///
    /// Malformed Markdown never fails: the parser is asked for a partial result,
    /// and if even that is impossible the source is kept as a single plain
    /// paragraph so no note text is ever lost on screen.
    ///
    /// - Parameter source: The raw note body as the user typed it.
    init(_ source: String) {
        let parsed = Self.parse(source)

        blocks = parsed
        sections = Self.sections(from: parsed)
    }

    /// Parses a source string into blocks.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: The blocks the source describes, or the source as one plain
    ///   paragraph when even a partial parse is impossible.
    private static func parse(_ source: String) -> [Block] {
        let parsed = parsedBlocks(of: source)

        guard InlineAttachmentMarker.mayAppear(in: source) else {
            return parsed
        }

        return withInlineAttachments(in: source, parsedAs: parsed) ?? parsed
    }

    /// Parses a source string into blocks, with every attachment marker left as
    /// the paragraph of text Foundation reads it as.
    ///
    /// - Parameter source: The raw note body, or a piece of one.
    /// - Returns: The blocks the source describes.
    private static func parsedBlocks(of source: String) -> [Block] {
        guard !source.isEmpty else {
            return []
        }

        guard let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return [.paragraph(AttributedString(source))]
        }

        return blocks(from: attributed)
    }

    /// Replaces the paragraphs that are attachment markers with attachment
    /// blocks, but only where the source proves they are blocks of their own.
    ///
    /// The syntax is invisible to Foundation, which reads a marker as ordinary
    /// text and discards the difference between one the user wrote and one they
    /// escaped. Rather than guessing from the parsed text, each candidate line
    /// is cut out of the source and the piece before it is parsed on its own. A
    /// candidate is accepted only when that piece and the marker line, parsed
    /// separately, are exactly the blocks the whole body already has at that
    /// position. That is the same argument ``MarkdownSourceMap`` makes about
    /// boundaries, for the same reason: Foundation stays the authority on what
    /// the Markdown means and this only decides where a placement is real.
    ///
    /// Everything a marker must not activate inside falls out of it. A marker
    /// in a fenced or indented code block does not parse to a paragraph, and
    /// cutting the source there produces blocks the body does not have. A
    /// marker in inline code or behind a backslash is not a candidate line at
    /// all, because the line holds a character besides the marker. A marker on
    /// the line after a paragraph is a continuation of that paragraph, and
    /// splitting it would produce two blocks where the body has one.
    ///
    /// A candidate that is refused is left in the text around it rather than
    /// abandoning the whole pass, so a note can hold a real placement and a
    /// marker written inside a code fence at the same time.
    ///
    /// - Parameters:
    ///   - source: The raw note body.
    ///   - expected: The blocks the whole body parsed to.
    /// - Returns: The blocks with placements resolved, or `nil` when the pieces
    ///   no longer add up to the parse, in which case the markers stay literal.
    private static func withInlineAttachments(
        in source: String,
        parsedAs expected: [Block]
    ) -> [Block]? {
        let candidates = InlineAttachmentMarker.candidateLines(in: source)

        guard !candidates.isEmpty else {
            return nil
        }

        var resolved: [Block] = []
        var consumed = 0
        var cursor = source.startIndex

        for candidate in candidates where candidate.range.lowerBound >= cursor {
            let line = source[candidate.range]
            let before = parsedBlocks(of: String(source[cursor..<candidate.range.lowerBound]))
            let marker = parsedBlocks(of: String(line))

            guard isParagraph(marker, spelling: line),
                  consumed + before.count + 1 <= expected.count,
                  Array(expected[consumed..<(consumed + before.count)]) == before,
                  expected[consumed + before.count] == marker[0]
            else {
                continue
            }

            resolved.append(contentsOf: before)
            resolved.append(.attachment(id: candidate.id))
            consumed += before.count + 1
            cursor = candidate.range.upperBound
        }

        let after = parsedBlocks(of: String(source[cursor...]))

        guard consumed + after.count == expected.count,
              Array(expected[consumed...]) == after
        else {
            return nil
        }

        resolved.append(contentsOf: after)

        return resolved
    }

    /// Whether a marker line parsed into one plain paragraph saying exactly
    /// what the line says.
    ///
    /// This is what tells a marker apart from the same characters indented into
    /// a code block, which parses to code rather than to a paragraph. Comparing
    /// against the line rather than against a canonical spelling is deliberate,
    /// so an identity written in lower case is recognized the same way.
    ///
    /// - Parameters:
    ///   - blocks: What the candidate line parsed to on its own.
    ///   - line: The candidate line, with any indentation and terminator.
    /// - Returns: `true` when the line is an ordinary paragraph of marker text.
    private static func isParagraph(_ blocks: [Block], spelling line: Substring) -> Bool {
        guard blocks.count == 1, case let .paragraph(text) = blocks[0] else {
            return false
        }

        return String(text.characters) == line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Divides parsed blocks into the regions read mode can fold.
    ///
    /// Division happens on the parsed `.thematicBreak` blocks, never on the
    /// source text. That is the whole correctness argument: a run of dashes
    /// inside a fenced or indented code block parses as code and is not a break,
    /// `Heading\n---` parses as a setext heading and is not a break, and every
    /// spelling the parser does accept as a break divides alike.
    ///
    /// A note that opens with a break gets no empty region above it, since there
    /// is nothing there to keep visible.
    ///
    /// - Parameter blocks: The document's blocks in reading order.
    /// - Returns: The regions, in reading order, with the breaks themselves
    ///   consumed.
    private static func sections(from blocks: [Block]) -> [Section] {
        var sections: [Section] = []
        var current: [Block] = []
        var precededByThematicBreak = false

        func flush() {
            guard precededByThematicBreak || !current.isEmpty else {
                return
            }

            sections.append(
                Section(
                    id: sections.count,
                    precededByThematicBreak: precededByThematicBreak,
                    blocks: current
                )
            )
            current = []
        }

        for block in blocks {
            if block == .thematicBreak {
                flush()
                precededByThematicBreak = true
            } else {
                current.append(block)
            }
        }

        flush()

        return sections
    }

    /// The document reduced to plain text, one line per block.
    ///
    /// Useful anywhere Markdown syntax would be noise rather than structure.
    var plainText: String {
        blocks.compactMap { block in
            switch block {
            case let .paragraph(text), let .blockQuote(text):
                String(text.characters)
            case let .heading(_, text):
                String(text.characters)
            case let .listItem(_, _, text):
                String(text.characters)
            case let .codeBlock(_, code):
                code
            case .thematicBreak, .attachment:
                nil
            }
        }
        .joined(separator: "\n")
    }

    /// Collapses a note body into a single line of prose for list previews.
    ///
    /// Only the opening of the body is parsed. A list row shows two lines, so
    /// parsing an entire long note to produce them is wasted work on a path that
    /// runs for every visible row on every list update.
    ///
    /// - Parameters:
    ///   - source: The raw note body.
    ///   - limit: How many characters to read before giving up. The default is
    ///     several times more than a row can display.
    /// - Returns: The text with Markdown syntax and line breaks removed.
    static func plainPreview(of source: String, limit: Int = 400) -> String {
        MarkdownDocument(opening(of: source, limit: limit))
            .plainText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The start of a note body, cut at a line boundary where possible.
    ///
    /// Cutting on a newline keeps the fragment closer to valid Markdown, so a
    /// construct is less likely to be split in half. Length is measured by
    /// walking at most `limit` characters rather than counting the whole string,
    /// which would defeat the purpose on a long note.
    ///
    /// - Parameters:
    ///   - source: The raw note body.
    ///   - limit: Maximum characters to keep.
    /// - Returns: The leading fragment, or the whole source when it is shorter.
    private static func opening(of source: String, limit: Int) -> String {
        guard let cut = source.index(
            source.startIndex,
            offsetBy: limit,
            limitedBy: source.endIndex
        ) else {
            return source
        }

        let head = source[source.startIndex..<cut]

        if let lastBreak = head.lastIndex(of: "\n"),
           head.distance(from: head.startIndex, to: lastBreak) > limit / 2 {
            return String(head[head.startIndex..<lastBreak])
        }

        return String(head)
    }

    /// Regroups parsed runs into blocks.
    ///
    /// Runs arrive flat, each tagged with the chain of block intents it sits
    /// inside, innermost first. Runs sharing a chain belong to the same block,
    /// so consecutive runs are gathered while that chain holds steady.
    private static func blocks(from attributed: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var currentIdentity: [Int] = []
        var currentIntent: PresentationIntent?
        var currentText = AttributedString()
        var isFirstRun = true

        func flush() {
            if let block = block(for: currentIntent, text: currentText) {
                blocks.append(block)
            }
            currentText = AttributedString()
        }

        for run in attributed.runs {
            let intent = run.presentationIntent
            let identity = intent?.components.map(\.identity) ?? []

            if isFirstRun {
                isFirstRun = false
            } else if identity != currentIdentity {
                flush()
            }

            currentIdentity = identity
            currentIntent = intent

            // A soft break is delivered as a space. Notes are written as prose
            // more often than as Markdown, so a line the user broke by hand is
            // kept broken rather than reflowed into the paragraph.
            if run.inlinePresentationIntent?.contains(.softBreak) == true {
                currentText.append(AttributedString("\n"))
            } else {
                currentText.append(attributed[run.range])
            }
        }

        if !isFirstRun {
            flush()
        }

        return blocks
    }

    /// Classifies one group of runs using its chain of block intents.
    ///
    /// - Parameters:
    ///   - intent: The presentation intent shared by the group.
    ///   - text: The group's accumulated text.
    /// - Returns: The matching block, or `nil` when the group carries no content.
    private static func block(
        for intent: PresentationIntent?,
        text: AttributedString
    ) -> Block? {
        var stripped = text
        stripped.presentationIntent = nil

        guard let components = intent?.components else {
            return stripped.characters.isEmpty ? nil : .paragraph(stripped)
        }

        var listDepth = 0
        var innermostOrdinal: Int?
        var isOrdered: Bool?
        var isQuoted = false

        // Components run innermost first, so the first list intent encountered
        // is the one that owns this item. Later list intents only add depth.
        for component in components {
            switch component.kind {
            case let .header(level):
                return .heading(level: level, text: stripped)
            case let .codeBlock(languageHint):
                let code = String(stripped.characters)
                    .trimmingCharacters(in: .newlines)
                return .codeBlock(language: languageHint, code: code)
            case .thematicBreak:
                return .thematicBreak
            case let .listItem(ordinal):
                if innermostOrdinal == nil {
                    innermostOrdinal = ordinal
                }
            case .orderedList:
                listDepth += 1
                if isOrdered == nil {
                    isOrdered = true
                }
            case .unorderedList:
                listDepth += 1
                if isOrdered == nil {
                    isOrdered = false
                }
            case .blockQuote:
                isQuoted = true
            default:
                break
            }
        }

        if stripped.characters.isEmpty {
            return nil
        }

        if let isOrdered {
            return .listItem(
                ordinal: isOrdered ? innermostOrdinal : nil,
                depth: max(0, listDepth - 1),
                text: stripped
            )
        }

        if isQuoted {
            return .blockQuote(stripped)
        }

        return .paragraph(stripped)
    }
}

/// Holds the most recent parse so unchanged text is not parsed again.
///
/// A reading view is re-evaluated for reasons that have nothing to do with its
/// text, and parsing a long note on each of those is the one piece of real work
/// on that path. A reference type is what makes the saving possible: a value
/// kept in SwiftUI state would have to be produced before it could be stored,
/// which is the cost being avoided.
///
/// The source is the cache key, so the document handed back always belongs to
/// the text that was asked for.
final class ParsedMarkdown {
    private var source = ""
    private var parsed = MarkdownDocument("")

    /// The parsed form of a note body.
    ///
    /// - Parameter source: The raw note body to render.
    /// - Returns: The document for that exact source, reusing the previous parse
    ///   when the text has not changed.
    func document(for source: String) -> MarkdownDocument {
        guard source != self.source else {
            return parsed
        }

        self.source = source
        parsed = MarkdownDocument(source)

        return parsed
    }
}
