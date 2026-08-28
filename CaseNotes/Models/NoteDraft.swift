//
//  NoteDraft.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

/// The user-editable fields of a note, held in memory while an edit is in progress.
///
/// Editing a SwiftData model directly writes straight through to the persistent
/// store, which leaves no way to abandon an edit. The editor therefore works on
/// a draft and only writes back through ``apply(to:at:)`` when the user saves,
/// so Cancel genuinely discards.
struct NoteDraft: Equatable {
    var title: String
    var body: String
    var eventDate: Date?
    var folder: Folder?

    init(
        title: String = "",
        body: String = "",
        eventDate: Date? = nil,
        folder: Folder? = nil
    ) {
        self.title = title
        self.body = body
        self.eventDate = eventDate
        self.folder = folder
    }

    /// Creates a draft seeded with the current contents of a stored note.
    ///
    /// - Parameter note: The note being edited. It is read from, never mutated.
    init(note: Note) {
        self.init(
            title: note.title,
            body: note.body,
            eventDate: note.eventDate,
            folder: note.folder
        )
    }

    /// The title as it will be stored, with surrounding whitespace removed.
    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the draft holds enough content to be saved.
    ///
    /// Notes are identified by their title throughout the interface, so a title
    /// that is empty or only whitespace is rejected.
    var isSavable: Bool {
        !normalizedTitle.isEmpty
    }

    /// Reports whether applying this draft would actually change the note.
    ///
    /// - Parameter note: The note this draft would be written to.
    /// - Returns: `true` when at least one stored field differs, filing included.
    func hasChanges(comparedTo note: Note) -> Bool {
        hasContentChanges(comparedTo: note)
            || folder?.persistentModelID != note.folder?.persistentModelID
    }

    /// Reports whether the note's authored content differs from this draft.
    ///
    /// Filing is deliberately excluded. Moving a note between folders organizes
    /// it rather than rewrites it, so it must not count as an edit. The body is
    /// compared verbatim because leading and trailing whitespace can be
    /// meaningful in note text.
    ///
    /// - Parameter note: The note this draft would be written to.
    /// - Returns: `true` when the title, body, or event date differs.
    func hasContentChanges(comparedTo note: Note) -> Bool {
        normalizedTitle != note.title
            || body != note.body
            || eventDate != note.eventDate
    }

    /// Writes the draft into a note, recording an edit timestamp only when the
    /// authored content actually changed.
    ///
    /// Opening a note and closing it again leaves the model untouched, so
    /// `updatedAt` keeps reflecting real edits rather than mere reads. Refiling
    /// is applied but does not move the timestamp, which keeps a note's edit
    /// date consistent whether it is moved from the editor or from the list.
    ///
    /// - Parameters:
    ///   - note: The persistent note to update in place.
    ///   - date: The timestamp recorded as the edit time. Injectable so tests
    ///     can assert on an exact value.
    /// - Returns: `true` when the note was modified in any way.
    @discardableResult
    func apply(to note: Note, at date: Date = Date()) -> Bool {
        guard hasChanges(comparedTo: note) else {
            return false
        }

        if hasContentChanges(comparedTo: note) {
            note.title = normalizedTitle
            note.body = body
            note.eventDate = eventDate
            note.updatedAt = date
        }

        note.folder = folder

        return true
    }
}
