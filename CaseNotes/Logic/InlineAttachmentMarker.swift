//
//  InlineAttachmentMarker.swift
//  CaseNotes
//
//  Created by q on 9/3/26.
//

import Foundation

/// The source syntax that places one of a note's files inside its Markdown.
///
/// A placement is a reference, never a copy. The stored body carries only the
/// attachment's identity, so renaming a file, changing what it is displayed as,
/// or moving the container leaves every placement pointing at the same
/// attachment. Identity is the one thing about an attachment that never
/// changes: ``AttachmentStore`` already names the file on disk after it, which
/// is why a placement can be a bare UUID rather than a path or a file name.
///
/// The syntax is deliberately not Markdown. Foundation's parser owns what the
/// body means, and a marker is written so that parser reads it as an ordinary
/// paragraph of text: nothing here changes how a note parses, and a note opened
/// by any other Markdown tool shows the marker as the literal text it is rather
/// than losing it.
///
/// Recognition is a whole line and nothing less. A marker is a document block,
/// so a line that holds anything besides the marker is prose, and
/// ``MarkdownDocument`` additionally proves that the line really is its own
/// block before treating it as a placement. That is what keeps a marker written
/// inside fenced code, indented code, inline code, or an escape sequence as the
/// literal text the author typed.
enum InlineAttachmentMarker {
    /// What a marker opens with.
    static let prefix = "{{attachment:"

    /// What a marker closes with.
    static let suffix = "}}"

    /// The source text that places an attachment.
    ///
    /// - Parameter id: The attachment's identity.
    /// - Returns: The marker to write into a note body.
    static func text(for id: UUID) -> String {
        "\(prefix)\(id.uuidString)\(suffix)"
    }

    /// Whether a body is worth scanning for markers at all.
    ///
    /// One substring search, and it is the reason a note without attachments
    /// pays nothing for this feature. Parsing runs on the keystroke path
    /// through ``MarkdownSourceMap``, so the common answer has to be cheap.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: `true` when the body could hold a marker.
    static func mayAppear(in source: String) -> Bool {
        source.contains(prefix)
    }

    /// The attachment a line refers to, if the line is a marker and nothing
    /// else.
    ///
    /// Surrounding whitespace is ignored, which covers the line's own
    /// terminator and the indentation Markdown allows before a paragraph. Any
    /// other character on the line, including a backslash escape or a backtick,
    /// means the line is prose and is answered with `nil`.
    ///
    /// - Parameter line: One line of a note body, with or without its
    ///   terminator.
    /// - Returns: The attachment's identity, or `nil` when the line is not a
    ///   marker.
    static func identifier(ofLine line: Substring) -> UUID? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix(prefix),
              trimmed.hasSuffix(suffix),
              trimmed.count > prefix.count + suffix.count
        else {
            return nil
        }

        return UUID(
            uuidString: String(trimmed.dropFirst(prefix.count).dropLast(suffix.count))
        )
    }

    /// Every line of a body that reads as a marker.
    ///
    /// These are candidates rather than placements. Whether a candidate is
    /// really a block of its own is decided by the parse, in
    /// ``MarkdownDocument``, so this walk knows nothing about Markdown beyond
    /// where its lines begin.
    ///
    /// - Parameter source: The raw note body.
    /// - Returns: One entry per candidate, in reading order, each covering the
    ///   whole line including its terminator.
    static func candidateLines(
        in source: String
    ) -> [(range: Range<String.Index>, id: UUID)] {
        guard mayAppear(in: source) else {
            return []
        }

        var candidates: [(range: Range<String.Index>, id: UUID)] = []
        var index = source.startIndex

        while index < source.endIndex {
            let terminator = source[index...].firstIndex(of: "\n") ?? source.endIndex
            let next = terminator < source.endIndex ? source.index(after: terminator) : source.endIndex

            if let id = identifier(ofLine: source[index..<terminator]) {
                candidates.append((index..<next, id))
            }

            index = next
        }

        return candidates
    }
}
