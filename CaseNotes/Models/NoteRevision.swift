//
//  NoteRevision.swift
//  CaseNotes
//
//  Created by q on 8/28/26.
//

import Foundation
import SwiftData

/// A previous authored state of a note, kept so it can be read again and
/// restored.
///
/// A revision holds the writing and nothing else. Filing, pinning, and drawings
/// are deliberately absent: those organize or decorate a note rather than say
/// what it says, so changing them is not a new version of the text. What is
/// stored is exactly the state ``NoteDraft`` treats as authored content, which
/// keeps version history and the edit timestamp describing the same thing.
///
/// Revisions are never edited once written. They are created by
/// ``NoteHistory``, read by the history screens, and removed only when their
/// note is deleted.
@Model
final class NoteRevision {
    var title: String
    var body: String
    var eventDate: Date?

    /// The note's edit timestamp while this state was the current one.
    ///
    /// This is the date to show a reader, because it is when the version was
    /// written. ``capturedAt`` is when it stopped being current, which is a
    /// different and much less useful answer to "when is this version from".
    var updatedAt: Date

    /// When this state was written to history, which is when it was replaced.
    ///
    /// Ordering uses this rather than ``updatedAt`` so history reads as the
    /// sequence of transitions that actually happened, including a restore that
    /// brings much older writing back to the top of the note.
    var capturedAt: Date

    /// The note this state belongs to.
    ///
    /// The owning side is ``Note/revisions``, which cascades, so history never
    /// outlives the note it describes.
    var note: Note?

    init(
        title: String = "",
        body: String = "",
        eventDate: Date? = nil,
        updatedAt: Date = Date(),
        capturedAt: Date = Date()
    ) {
        self.title = title
        self.body = body
        self.eventDate = eventDate
        self.updatedAt = updatedAt
        self.capturedAt = capturedAt
    }

    /// The title to show, falling back to the same placeholder notes use.
    ///
    /// Titles are required before a note can be saved, so this only matters for
    /// history written before that rule reached a given store. Sharing the
    /// fallback keeps a version from being labelled differently to the note it
    /// came from.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    /// Whether a note currently says exactly what this revision says.
    ///
    /// Used to keep restoring a version that is already current from writing a
    /// duplicate entry into history.
    ///
    /// - Parameter note: The note to compare against.
    /// - Returns: `true` when title, body, and event date all match.
    func matchesAuthoredState(of note: Note) -> Bool {
        title == note.title
            && body == note.body
            && eventDate == note.eventDate
    }
}
