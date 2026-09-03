//
//  MarkdownSourceMap.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation

/// A note body divided into the source regions live preview can edit one at a
/// time.
///
/// ``MarkdownDocument`` answers what a note means; it deliberately does not say
/// where in the source each block came from, because Foundation's Markdown
/// parser discards the syntax on the way to `AttributedString`. Live preview
/// needs the other half: which characters of the stored body produced the block
/// under the caret, so that block can be swapped for its own source without
/// touching anything around it.
///
/// The division is proposed and then proved rather than parsed a second time. A
/// cheap scan proposes boundaries, and every candidate region is only accepted
/// once parsing it on its own produces exactly the blocks the whole-document
/// parse produced at that position. Foundation therefore stays the single
/// authority on what the Markdown means, and this type owns only where it is
/// safe to cut.
///
/// Two invariants hold for every map and are covered by tests:
///
/// - the regions are contiguous and cover the source exactly, so joining their
///   text back together reproduces the body character for character
/// - the regions' blocks, in order, are the document's blocks
struct MarkdownSourceMap: Equatable {
    /// One independently editable piece of a note body.
    struct Region: Equatable, Identifiable {
        /// The region's place in reading order, counted from zero.
        ///
        /// Identity is position, matching how ``MarkdownDocument/Section``
        /// identifies a foldable region. A region's identity is only meaningful
        /// for as long as the source is unchanged.
        let id: Int

        /// The characters of the note body this region owns, counted in UTF-16
        /// code units from the start of it.
        ///
        /// Spans are half open and abut, so the region after this one starts
        /// exactly where it ends. Trailing blank lines belong to the region
        /// above them, which is what keeps the separation between two blocks
        /// editable from the block before it.
        ///
        /// A span rather than a `String.Index` range because a region has to
        /// survive an edit to the body: an index belongs to the string it was
        /// made from, while an offset can be moved by the length of what was
        /// typed. UIKit text views measure in UTF-16 as well, so this is also
        /// the form a caret position is exchanged in. Offsets are accumulated
        /// while the regions are built rather than measured one region at a
        /// time, which would walk the body once per region.
        let utf16Range: Range<Int>

        /// What the region's source parses to, taken from the whole-document
        /// parse rather than from parsing the region again.
        let blocks: [MarkdownDocument.Block]

        /// Whether the region holds no blocks at all.
        ///
        /// True only for a trailing run of blank lines, or for an empty body.
        /// The region still owns real characters and still has to be reachable,
        /// which is why a view gives it a target rather than skipping it.
        var isEmpty: Bool {
            blocks.isEmpty
        }

        /// The block that decides how the region's source is set while it is
        /// being edited, so a heading stays a heading with its syntax showing.
        var leadingBlock: MarkdownDocument.Block? {
            blocks.first
        }

        /// The same region moved along the body and renumbered.
        ///
        /// An edit inside one region shifts everything below it, which changes
        /// where those regions sit without changing what they say.
        ///
        /// - Parameters:
        ///   - offset: How far to move it, in UTF-16 code units.
        ///   - id: Its place in the map being assembled.
        /// - Returns: The moved region.
        func moved(by offset: Int, numbered id: Int) -> Region {
            Region(
                id: id,
                utf16Range: (utf16Range.lowerBound + offset)..<(utf16Range.upperBound + offset),
                blocks: blocks
            )
        }
    }

    /// The body the map describes. Every region range indexes into this string.
    let source: String

    let regions: [Region]

    /// Whether every boundary in this division was proved against the parse.
    ///
    /// True for a division of a whole body, false for one a keystroke repaired
    /// locally, which trusts its caller rather than proving anything. The two
    /// agree for an ordinary edit and can differ while Markdown is half typed,
    /// so a caller that needs a settled answer has to know which kind it holds.
    ///
    /// It is what lets a division be reused instead of repeated: a proven map
    /// whose ``source`` is still the body being shown is the same answer
    /// dividing again would produce, and dividing a long note is tens of
    /// milliseconds of main-thread work.
    let isProven: Bool

    /// Divides a note body into editable regions.
    ///
    /// - Parameter source: The raw note body, exactly as it is stored.
    init(_ source: String) {
        self.source = source
        regions = Self.divide(source)
        isProven = true
    }

    /// Assembles a map from regions that are already known to cover a body.
    ///
    /// Dividing a whole note costs more than parsing it, because every boundary
    /// is proved by parsing the text it cuts. That price is fine when a note is
    /// opened or a region is entered, and it is not fine on a keystroke: a note
    /// long enough to take tens of milliseconds would let queued keystrokes
    /// pile up behind the division and be overwritten by the state it produced.
    /// Live preview therefore re-divides only the span it just edited and
    /// reassembles the map around it through this initializer, which trusts its
    /// caller rather than proving anything.
    ///
    /// The result is a working division rather than a proven one, and the next
    /// whole-body division replaces it.
    ///
    /// - Parameters:
    ///   - source: The body the regions describe.
    ///   - regions: Contiguous regions covering it, in reading order and
    ///     already numbered from zero.
    init(source: String, regions: [Region]) {
        self.source = source
        self.regions = regions
        isProven = false
    }

    /// The text a region owns.
    ///
    /// - Parameter region: A region of this map.
    /// - Returns: The characters of ``source`` it covers.
    func text(of region: Region) -> String {
        Self.substring(of: source, utf16Range: region.utf16Range)
    }

    /// This division repaired around the span an edit has just changed.
    ///
    /// Only the span is divided again. The regions above it keep the offsets
    /// they already had, because an edit inside the span cannot move them, and
    /// the regions below it move by whatever the span's length changed by.
    ///
    /// This is the keystroke path, and its cost is the length of one region
    /// rather than the length of a note. Dividing the whole note here instead
    /// took long enough on a long note that keys pressed during it queued up
    /// behind it and were then overwritten by the state it produced, which lost
    /// real text. It was found by typing quickly, not by reading the code.
    ///
    /// For an ordinary edit the answer matches a whole-body division. It can
    /// differ while Markdown is half typed, such as an unclosed fence whose
    /// effect on the text below it a local repair cannot see; entering a region
    /// divides the whole body again and settles it.
    ///
    /// - Parameters:
    ///   - body: The note body after the edit.
    ///   - indices: The regions the span replaces, which must be contiguous and
    ///     start where the span starts.
    ///   - span: The span's place in `body`, in UTF-16 code units.
    /// - Returns: The repaired division, or `nil` when the arguments do not
    ///   describe this map.
    func rebuilt(
        from body: String,
        replacing indices: Range<Int>,
        covering span: Range<Int>
    ) -> MarkdownSourceMap? {
        guard indices.lowerBound >= 0,
              indices.upperBound <= regions.count,
              !indices.isEmpty,
              regions[indices.lowerBound].utf16Range.lowerBound == span.lowerBound
        else {
            return nil
        }

        let shift = span.upperBound - regions[indices.upperBound - 1].utf16Range.upperBound
        let parts = MarkdownSourceMap(Self.substring(of: body, utf16Range: span)).regions

        var rebuilt = Array(regions[..<indices.lowerBound])

        for part in parts {
            rebuilt.append(part.moved(by: span.lowerBound, numbered: rebuilt.count))
        }

        for region in regions[indices.upperBound...] {
            rebuilt.append(region.moved(by: shift, numbered: rebuilt.count))
        }

        return MarkdownSourceMap(source: body, regions: rebuilt)
    }

    /// The region that owns a UTF-16 offset into the source.
    ///
    /// - Parameter offset: A position measured in UTF-16 code units from the
    ///   start of ``source``.
    /// - Returns: The owning region, or `nil` when the map has none.
    func region(containingUTF16Offset offset: Int) -> Region? {
        guard let last = regions.last else {
            return nil
        }

        guard offset < last.utf16Range.upperBound else {
            return last
        }

        return regions.first { $0.utf16Range.contains(offset) } ?? regions.first
    }

    /// The region with a given identity.
    ///
    /// - Parameter id: A region identity from a previous division of the same
    ///   source.
    /// - Returns: The region, or `nil` when the source has changed enough that
    ///   the identity no longer exists.
    func region(id: Int) -> Region? {
        regions.indices.contains(id) ? regions[id] : nil
    }

    // MARK: Source arithmetic

    /// The text a UTF-16 range names.
    ///
    /// Offsets are clamped and rounded onto character boundaries, so a range
    /// that has gone stale against an edit yields a shorter answer rather than
    /// a crash or a half of an emoji.
    ///
    /// - Parameters:
    ///   - source: The body to read from.
    ///   - utf16Range: The span, measured in UTF-16 code units.
    /// - Returns: The characters in that span.
    static func substring(of source: String, utf16Range: Range<Int>) -> String {
        String(source[characterRange(in: source, utf16Range: utf16Range)])
    }

    /// A body with one UTF-16 span replaced.
    ///
    /// This is the only way live preview writes back what was typed: an edit is
    /// applied to the region's own span, and every character outside it is
    /// carried through untouched. Nothing is normalized and nothing is
    /// reformatted, so the stored Markdown stays exactly what the user wrote.
    ///
    /// - Parameters:
    ///   - source: The body being edited.
    ///   - utf16Range: The span the edit replaces.
    ///   - text: What to put there.
    /// - Returns: The rewritten body.
    static func replacing(
        _ source: String,
        utf16Range: Range<Int>,
        with text: String
    ) -> String {
        source.replacingCharacters(
            in: characterRange(in: source, utf16Range: utf16Range),
            with: text
        )
    }

    /// Turns a UTF-16 span into character indices, clamped to the body.
    ///
    /// - Parameters:
    ///   - source: The body being addressed.
    ///   - utf16Range: The span, measured in UTF-16 code units.
    /// - Returns: The equivalent character range.
    private static func characterRange(
        in source: String,
        utf16Range: Range<Int>
    ) -> Range<String.Index> {
        let length = source.utf16.count
        let lower = min(max(utf16Range.lowerBound, 0), length)
        let upper = min(max(utf16Range.upperBound, lower), length)

        let start = String.Index(utf16Offset: lower, in: source)
        let end = String.Index(utf16Offset: upper, in: source)

        return start..<max(start, end)
    }

    // MARK: Division

    /// Builds the regions for a source string.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: The regions, in reading order.
    private static func divide(_ source: String) -> [Region] {
        let blocks = MarkdownDocument(source).blocks

        guard !source.isEmpty else {
            // An empty body still needs somewhere for a caret to go.
            return [Region(id: 0, utf16Range: 0..<0, blocks: [])]
        }

        // Walked once and shared by both passes. Rescanning the body for every
        // region would make dividing a long note quadratic in its length.
        let lines = lines(of: source)

        let coarse = assemble(
            source,
            boundaries: paragraphBoundaries(of: source, lines: lines),
            expected: blocks
        ) ?? [(source.startIndex..<source.endIndex, blocks)]

        var refined: [(range: Range<String.Index>, blocks: [MarkdownDocument.Block])] = []

        for piece in coarse {
            // A piece holding one block cannot be cut into anything smaller that
            // still parses, so the second pass is only worth running on the
            // pieces that gathered several: a tight list, or a heading with no
            // blank line under it.
            guard piece.blocks.count > 1,
                  let parts = assemble(
                      source,
                      boundaries: lineBoundaries(in: piece.range, lines: lines),
                      expected: piece.blocks
                  )
            else {
                refined.append(piece)
                continue
            }

            refined.append(contentsOf: parts)
        }

        var start = 0

        return refined.enumerated().map { index, piece in
            let end = start + source[piece.range].utf16.count
            defer { start = end }

            return Region(id: index, utf16Range: start..<end, blocks: piece.blocks)
        }
    }

    /// Cuts a span of source into regions along candidate boundaries.
    ///
    /// Candidates are only proposals. A cut is accepted when the text between
    /// two of them parses on its own into exactly the blocks the document has at
    /// that position, which is what stops a boundary landing inside a fenced
    /// block, an indented code block, a nested list, or anything else whose
    /// meaning depends on the lines around it.
    ///
    /// The walk is greedy for the shortest region that validates, and steps back
    /// when a later region cannot be made to work: an accepted region is
    /// re-opened and extended by one candidate before the walk continues. That
    /// is what divides `- a`, `  - b`, `- c` into the nested item travelling
    /// with its parent and the third item standing alone. The whole span always
    /// validates against the whole block list, so the walk cannot fail to
    /// terminate; a budget guards against a pathological source costing more
    /// attempts than a division is worth.
    ///
    /// - Parameters:
    ///   - source: The body the boundaries index into.
    ///   - boundaries: Candidate cut positions, opening with the span's start
    ///     and closing with its end.
    ///   - expected: The blocks the span produces when parsed whole.
    /// - Returns: The accepted regions, or `nil` when the budget ran out or the
    ///   span cannot be divided at these boundaries.
    private static func assemble(
        _ source: String,
        boundaries: [String.Index],
        expected: [MarkdownDocument.Block]
    ) -> [(range: Range<String.Index>, blocks: [MarkdownDocument.Block])]? {
        guard boundaries.count > 2 else {
            // Nothing to cut: one candidate region, which is the span itself.
            guard let first = boundaries.first, let last = boundaries.last else {
                return nil
            }

            return [(first..<last, expected)]
        }

        var accepted: [(start: Int, end: Int, blocks: [MarkdownDocument.Block])] = []
        var start = 0
        var minimumEnd = 1
        var consumed = 0
        var budget = 8 * boundaries.count + 32

        while start < boundaries.count - 1 {
            var chosen: (end: Int, blocks: [MarkdownDocument.Block])?

            for end in minimumEnd..<boundaries.count {
                budget -= 1

                guard budget > 0 else {
                    return nil
                }

                let text = String(source[boundaries[start]..<boundaries[end]])
                let parsed = MarkdownDocument(text).blocks

                // Whitespace between blocks parses to nothing. It belongs to the
                // region above it rather than becoming a region of its own,
                // which would own characters no caret could reach and would draw
                // as a gap in a note that has none. A body holding nothing but
                // blank lines is the one case with no region above to join, and
                // is the only way an empty region is produced.
                if parsed.isEmpty,
                   !(accepted.isEmpty && end == boundaries.count - 1 && consumed == expected.count) {
                    continue
                }

                guard consumed + parsed.count <= expected.count,
                      Array(expected[consumed..<(consumed + parsed.count)]) == parsed
                else {
                    continue
                }

                chosen = (end, parsed)
                break
            }

            if let chosen {
                accepted.append((start, chosen.end, chosen.blocks))
                consumed += chosen.blocks.count
                start = chosen.end
                minimumEnd = start + 1
                continue
            }

            // Nothing starting here works. Re-open the region before it and make
            // it swallow one more candidate, which is the only way a construct
            // whose meaning spans a boundary can be kept whole.
            guard let previous = accepted.popLast() else {
                return nil
            }

            consumed -= previous.blocks.count
            start = previous.start
            minimumEnd = previous.end + 1
        }

        guard consumed == expected.count else {
            return nil
        }

        return accepted.map {
            (boundaries[$0.start]..<boundaries[$0.end], $0.blocks)
        }
    }

    // MARK: Candidate boundaries

    /// Positions where a new block plausibly starts, taken as the line after a
    /// blank one.
    ///
    /// This is the cheap first proposal and knows nothing about Markdown beyond
    /// the fact that authors separate blocks with blank lines. Everything it
    /// gets wrong, such as a blank line inside a fenced block or inside indented
    /// code, is caught by validation and merged back.
    ///
    /// - Parameters:
    ///   - source: The raw note body.
    ///   - lines: The body's lines, already walked.
    /// - Returns: The candidates, opening with the start of the body and closing
    ///   with its end.
    private static func paragraphBoundaries(
        of source: String,
        lines: [(start: String.Index, isBlank: Bool)]
    ) -> [String.Index] {
        var boundaries = [source.startIndex]
        var previousWasBlank = false

        for line in lines {
            if !line.isBlank, previousWasBlank, line.start > source.startIndex {
                boundaries.append(line.start)
            }

            previousWasBlank = line.isBlank
        }

        boundaries.append(source.endIndex)

        return boundaries
    }

    /// Every line start inside a region, used for the second and finer pass.
    ///
    /// - Parameters:
    ///   - range: The region being subdivided.
    ///   - lines: The body's lines, already walked.
    /// - Returns: The candidates, opening with the region's start and closing
    ///   with its end.
    private static func lineBoundaries(
        in range: Range<String.Index>,
        lines: [(start: String.Index, isBlank: Bool)]
    ) -> [String.Index] {
        var boundaries = [range.lowerBound]

        for line in lines where line.start > range.lowerBound && line.start < range.upperBound {
            boundaries.append(line.start)
        }

        boundaries.append(range.upperBound)

        return boundaries
    }

    /// Walks a string's lines, reporting where each begins and whether it holds
    /// anything but whitespace.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: One entry per line, in order.
    private static func lines(of source: String) -> [(start: String.Index, isBlank: Bool)] {
        var lines: [(start: String.Index, isBlank: Bool)] = []
        var index = source.startIndex

        while index < source.endIndex {
            let end = source[index...].firstIndex(of: "\n") ?? source.endIndex

            lines.append((index, source[index..<end].allSatisfy(\.isWhitespace)))

            index = end < source.endIndex ? source.index(after: end) : source.endIndex
        }

        return lines
    }
}

/// Holds the most recent division so unchanged text is not divided again.
///
/// Live preview asks for the map on every update, including the many that have
/// nothing to do with the body, and dividing costs more than a plain parse
/// because it proves its candidates by parsing them. A reference type is what
/// makes the saving possible, for the same reason ``ParsedMarkdown`` is one.
final class ParsedMarkdownSource {
    private var map = MarkdownSourceMap("")

    /// The division of a note body.
    ///
    /// - Parameter source: The raw note body being edited.
    /// - Returns: The map for that exact source, reusing the previous division
    ///   when the text has not changed.
    func map(for source: String) -> MarkdownSourceMap {
        guard source != map.source else {
            return map
        }

        map = MarkdownSourceMap(source)

        return map
    }
}
