//
//  NoteExport.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Markdown text.
    ///
    /// The SDK exposes no built-in Markdown constant, so the type is resolved
    /// from the file extension and falls back to plain text on any system that
    /// does not know it. Either way the shared file keeps its `.md` name.
    static var noteMarkdown: UTType {
        UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    }
}

/// Builds the text CaseNotes hands to the share sheet.
///
/// Exports carry only what the user wrote: the title, the event date they set,
/// and the note body. Bookkeeping the app keeps for itself, such as creation and
/// edit timestamps or pinned state, is deliberately left out, since it is app
/// state rather than note content.
///
/// Formatting is pure and deterministic so it can be asserted on in tests.
enum NoteExport {
    /// Footer identifying the app in shared copies.
    ///
    /// Applied to shares and exported files, never to a plain copy, so pasting a
    /// note into another document never drags along wording the user did not write.
    static let attribution = "Created with CaseNotes"

    /// Renders a note as a Markdown document.
    ///
    /// The body is already Markdown, so it is passed through untouched and the
    /// user's formatting survives the round trip.
    ///
    /// - Parameters:
    ///   - note: The note to render.
    ///   - includingAttribution: Whether to append the CaseNotes footer.
    ///   - locale: Locale used to format the event date.
    ///   - timeZone: Time zone used to format the event date.
    /// - Returns: A Markdown document with no trailing whitespace.
    static func markdown(
        for note: Note,
        includingAttribution: Bool,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var sections: [String] = ["# \(displayTitle(for: note))"]

        if let eventDate = note.eventDate {
            let formatted = eventDate.formatted(
                Date.FormatStyle(
                    date: .long,
                    time: .omitted,
                    locale: locale,
                    calendar: locale.calendar,
                    timeZone: timeZone
                )
            )
            sections.append("*Event date: \(formatted)*")
        }

        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            sections.append(body)
        }

        if includingAttribution {
            sections.append("---")
            sections.append(attribution)
        }

        return sections.joined(separator: "\n\n")
    }

    /// The file name to suggest when exporting a note as a document.
    ///
    /// - Parameter note: The note being exported.
    /// - Returns: A `.md` file name safe for the file system and for sharing.
    static func suggestedFileName(for note: Note) -> String {
        "\(fileBaseName(for: note)).md"
    }

    /// The file name without its extension.
    ///
    /// Characters that are unsafe in a path become separators rather than being
    /// deleted, so a title broken across lines does not have its words run
    /// together. Runs of whitespace are then collapsed and the result is capped
    /// so no share target has to truncate it.
    ///
    /// - Parameter note: The note being exported.
    /// - Returns: A sanitized base name, never empty.
    static func fileBaseName(for note: Note) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)

        let cleaned = displayTitle(for: note)
            .components(separatedBy: unsafe)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !cleaned.isEmpty else {
            return "Note"
        }

        return String(cleaned.prefix(60))
    }

    /// The note's title, or a placeholder when it has none.
    ///
    /// - Parameter note: The note being exported.
    /// - Returns: A non-empty title.
    static func displayTitle(for note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }
}

/// A note packaged as a Markdown file for the share sheet.
///
/// Sharing a real `.md` file rather than a string lets receiving apps save it,
/// open it in an editor, or attach it, with the Markdown source intact.
struct MarkdownNoteFile: Transferable, Sendable {
    let fileName: String
    let markdown: String

    /// - Parameters:
    ///   - note: The note to package.
    ///   - locale: Locale used to format the event date.
    ///   - timeZone: Time zone used to format the event date.
    init(
        note: Note,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        fileName = NoteExport.suggestedFileName(for: note)
        markdown = NoteExport.markdown(
            for: note,
            includingAttribution: true,
            locale: locale,
            timeZone: timeZone
        )
    }

    nonisolated static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .noteMarkdown) { file in
            Data(file.markdown.utf8)
        }
        .suggestedFileName { $0.fileName }
    }
}
