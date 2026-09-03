//
//  InlineAttachments.swift
//  CaseNotes
//
//  Created by q on 9/3/26.
//

import Foundation

/// Where one attachment is placed inside a note body.
///
/// A placement is identified by position rather than by the attachment it
/// refers to, because the same file may legitimately be placed twice. The
/// identity is the region's place in the division, which matches how
/// ``MarkdownSourceMap/Region`` and ``MarkdownDocument/Section`` identify
/// themselves and is meaningful only for as long as the body is unchanged.
struct InlineAttachmentPlacement: Equatable, Identifiable {
    /// The placement's region in the division, counted from zero.
    let id: Int

    /// The attachment the marker names.
    let attachmentID: UUID

    /// The span of the body the placement owns, in UTF-16 code units.
    ///
    /// It is the region's whole span, so it includes the blank lines that
    /// separate the marker from the block below it. That is what lets a
    /// placement be lifted out or moved without leaving a stray gap behind.
    let utf16Range: Range<Int>
}

/// Placing a note's own files inside its Markdown, and moving them around.
///
/// Every operation here is a rewrite of the note body and nothing else. No file
/// is copied, no record is written, and no attachment is created or destroyed:
/// a placement refers to an attachment the note already has, so inserting one
/// is authoring text and removing one is deleting text. That separation is the
/// point of the feature, and it is why the ordinary draft, timestamp, and
/// version history rules cover placements without a single exception.
///
/// The body is never normalized. An edit replaces one span through
/// ``MarkdownSourceMap/replacing(_:utf16Range:with:)`` and everything outside
/// it is carried through character for character, so a note keeps the Markdown
/// its author wrote.
enum InlineAttachments {
    /// Which way a placement is being moved through the document.
    enum MoveDirection {
        case up
        case down
    }

    /// A body rewritten by an insertion, with somewhere to put the caret.
    struct Insertion: Equatable {
        /// The note body after the marker was written into it.
        let source: String

        /// Where the marker itself now sits, in UTF-16 code units.
        let markerUTF16Range: Range<Int>

        /// Where the caret belongs afterwards, which is the end of the marker.
        var caretUTF16Offset: Int {
            markerUTF16Range.upperBound
        }
    }

    /// The placements in a note body, in reading order.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: One entry per placement.
    static func placements(in source: String) -> [InlineAttachmentPlacement] {
        placements(in: MarkdownSourceMap(source))
    }

    /// The placements a division already describes.
    ///
    /// Taking the division rather than the body is what lets live preview list
    /// placements without dividing the note a second time.
    ///
    /// - Parameter map: A division of the note body.
    /// - Returns: One entry per placement, in reading order.
    static func placements(in map: MarkdownSourceMap) -> [InlineAttachmentPlacement] {
        map.regions.compactMap { region in
            guard let attachmentID = self.attachmentID(of: region) else {
                return nil
            }

            return InlineAttachmentPlacement(
                id: region.id,
                attachmentID: attachmentID,
                utf16Range: region.utf16Range
            )
        }
    }

    /// The attachment a region places, when the region is a placement and
    /// nothing else.
    ///
    /// A region holding a marker alongside other blocks is not offered as a
    /// placement, because moving or removing it would take that other writing
    /// with it. The division separates blocks by line, so this is the shape a
    /// marker actually lands in.
    ///
    /// - Parameter region: A region of a division.
    /// - Returns: The attachment's identity, or `nil` when the region is not a
    ///   placement on its own.
    static func attachmentID(of region: MarkdownSourceMap.Region) -> UUID? {
        guard region.blocks.count == 1,
              case let .attachment(id) = region.blocks[0]
        else {
            return nil
        }

        return id
    }

    /// Writes a marker into a note body at an editing position.
    ///
    /// An attachment is a document block, so it is placed at the boundary of
    /// the block the caret is in rather than between two words: at the start of
    /// that block when the caret is at its very start, and after it otherwise.
    /// That is what keeps an insertion from cutting a heading in half or
    /// breaking a fenced block open, and it is the only place a caret position
    /// is interpreted rather than obeyed.
    ///
    /// The separators around the marker are the only characters this adds. A
    /// blank line is written on each side, unless the body already provides
    /// one or the marker lands against the start or the end of the note, which
    /// is what keeps the marker a block of its own without reformatting
    /// anything around it.
    ///
    /// - Parameters:
    ///   - id: The attachment being placed.
    ///   - source: The note body being edited.
    ///   - offset: The caret's position, in UTF-16 code units. Positions
    ///     outside the body are clamped onto it.
    /// - Returns: The rewritten body and where the marker landed.
    static func inserting(
        _ id: UUID,
        into source: String,
        atUTF16Offset offset: Int
    ) -> Insertion {
        insertingMarker(
            InlineAttachmentMarker.text(for: id),
            into: source,
            atUTF16Offset: blockBoundary(for: offset, in: MarkdownSourceMap(source))
        )
    }

    /// Moves a placement one block through the document.
    ///
    /// The marker is lifted out of the body and written back on the far side of
    /// its neighbour, which is the same insertion an author would make by hand.
    /// Only those characters move: the neighbouring block is not reparsed, not
    /// reflowed, and not rewritten.
    ///
    /// A region owns the blank line below it, so the separator that travels
    /// with a marker is the one under it. Moving a marker away from the end of
    /// a note therefore leaves the blank line that was above it as a trailing
    /// one, which is a separator staying where it was rather than text being
    /// changed. Nothing else is touched, and nothing is trimmed: normalizing a
    /// note because a block moved would be a larger change than the move.
    ///
    /// - Parameters:
    ///   - id: The placement's identity, which is its region in the division.
    ///   - direction: Which way to move it.
    ///   - source: The note body being edited.
    /// - Returns: The rewritten body, or `nil` when there is no such placement
    ///   or nothing on that side of it to move past.
    static func moving(
        placement id: Int,
        _ direction: MoveDirection,
        in source: String
    ) -> Insertion? {
        let map = MarkdownSourceMap(source)

        guard let placement = map.region(id: id),
              let attachmentID = attachmentID(of: placement)
        else {
            return nil
        }

        let neighbourID = direction == .up ? id - 1 : id + 1

        guard let neighbour = map.region(id: neighbourID) else {
            return nil
        }

        let target = direction == .up
            ? neighbour.utf16Range.lowerBound
            : neighbour.utf16Range.upperBound

        let lifted = placement.utf16Range
        let body = MarkdownSourceMap.replacing(source, utf16Range: lifted, with: "")

        // Everything after the lifted span moved up by its length. The
        // neighbour is on one side or the other, never inside it, so this is
        // the whole correction needed.
        let corrected = target > lifted.lowerBound ? target - lifted.count : target

        return inserting(attachmentID, into: body, atUTF16Offset: corrected)
    }

    /// Takes a placement out of a note body.
    ///
    /// Only the marker and the blank line under it go. The attachment stays on
    /// the note, its file stays on disk, and it can be placed again. Removing a
    /// reference and deleting a file are deliberately different actions, and
    /// only the second one is destructive.
    ///
    /// - Parameters:
    ///   - id: The placement's identity, which is its region in the division.
    ///   - source: The note body being edited.
    /// - Returns: The rewritten body, or `nil` when there is no such placement.
    static func removing(placement id: Int, in source: String) -> String? {
        let map = MarkdownSourceMap(source)

        guard let placement = map.region(id: id),
              attachmentID(of: placement) != nil
        else {
            return nil
        }

        return MarkdownSourceMap.replacing(
            source,
            utf16Range: placement.utf16Range,
            with: ""
        )
    }

    // MARK: Source arithmetic

    /// The position a caret means when an attachment is placed from it.
    ///
    /// - Parameters:
    ///   - offset: The caret's position in UTF-16 code units.
    ///   - map: The division of the body the caret sits in.
    /// - Returns: The boundary of the block the caret is in.
    private static func blockBoundary(
        for offset: Int,
        in map: MarkdownSourceMap
    ) -> Int {
        let clamped = min(max(offset, 0), map.source.utf16.count)

        guard let region = map.region(containingUTF16Offset: clamped) else {
            return clamped
        }

        return clamped <= region.utf16Range.lowerBound
            ? region.utf16Range.lowerBound
            : region.utf16Range.upperBound
    }

    /// Writes a marker at a boundary, with the blank lines it needs on either
    /// side and no others.
    ///
    /// - Parameters:
    ///   - marker: The marker text.
    ///   - source: The note body being edited.
    ///   - offset: A block boundary in the body, in UTF-16 code units.
    /// - Returns: The rewritten body and where the marker landed.
    private static func insertingMarker(
        _ marker: String,
        into source: String,
        atUTF16Offset offset: Int
    ) -> Insertion {
        let before = MarkdownSourceMap.substring(of: source, utf16Range: 0..<offset)
        let after = MarkdownSourceMap.substring(
            of: source,
            utf16Range: offset..<source.utf16.count
        )

        let lead = separator(endingBefore: before)
        let trail = separator(startingAfter: after)
        let start = before.utf16.count + lead.utf16.count

        return Insertion(
            source: before + lead + marker + trail + after,
            markerUTF16Range: start..<(start + marker.utf16.count)
        )
    }

    /// The newlines needed between what is above and a marker.
    ///
    /// - Parameter before: The body up to the insertion point.
    /// - Returns: Nothing, one newline, or a blank line.
    private static func separator(endingBefore before: String) -> String {
        if before.isEmpty || before.hasSuffix("\n\n") {
            return ""
        }

        return before.hasSuffix("\n") ? "\n" : "\n\n"
    }

    /// The newlines needed between a marker and what is below it.
    ///
    /// - Parameter after: The body from the insertion point on.
    /// - Returns: Nothing, one newline, or a blank line.
    private static func separator(startingAfter after: String) -> String {
        if after.isEmpty || after.hasPrefix("\n\n") {
            return ""
        }

        return after.hasPrefix("\n") ? "\n" : "\n\n"
    }
}
