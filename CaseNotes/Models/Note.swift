//
//  Note.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool = false
    var eventDate: Date?

    /// The folder this note is filed in, or `nil` when it is unfiled.
    ///
    /// Optional by design. Filing is never required, and it is what lets notes
    /// outlive the folder they were in.
    var folder: Folder?

    /// An optional sketch attached to this note.
    ///
    /// Cascading is correct here, unlike for folders: a drawing is part of the
    /// note rather than a place it lives, so deleting the note deletes it. The
    /// relationship also keeps the drawing's bytes out of the way until a note
    /// is opened.
    @Relationship(deleteRule: .cascade, inverse: \NoteDrawing.note)
    var drawing: NoteDrawing?

    init(
        title: String = "",
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        eventDate: Date? = nil,
        folder: Folder? = nil
    ) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.eventDate = eventDate
        self.folder = folder
    }

    /// The title to show, falling back to a placeholder for untitled notes.
    ///
    /// Notes are identified by title throughout the interface, so every surface
    /// needs the same fallback. Keeping it on the model stops the list, the
    /// reader, and exports from drifting apart.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }
}
