//
//  PreNestedFolderSchema.swift
//  CaseNotesTests
//
//  Created by q on 8/29/26.
//

import Foundation
import SwiftData

/// The models exactly as they stood before folders could hold folders.
///
/// A migration test needs a store whose `Folder` entity genuinely has no parent
/// or children relationship, and the current model cannot write one: adding the
/// self-relation changed the entity, so a store written with today's `Folder`
/// would already be the new schema and the test would prove nothing. Naming
/// fewer models does not help either, because SwiftData resolves a schema
/// through relationships and registers every entity it can reach.
///
/// These declarations are therefore the only way to write the older store.
/// Entity names come from the class names, which are the same as the app's, so a
/// store written here is the same store the previous build would have left
/// behind. Nothing in the app refers to these types, and they must not gain
/// properties: their whole purpose is to stay frozen at the flat-folder schema.
///
/// The earlier freeze in ``PreRevisionSchema`` covers a different point in the
/// history and is left alone.
enum PreNestedFolderSchema {
    /// Every model registered by the build before folders nested.
    static let models: [any PersistentModel.Type] = [
        Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
    ]

    @Model
    final class Note {
        var title: String
        var body: String
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool = false
        var eventDate: Date?
        var folder: Folder?

        @Relationship(deleteRule: .cascade, inverse: \NoteDrawing.note)
        var drawing: NoteDrawing?

        @Relationship(deleteRule: .cascade, inverse: \NoteRevision.note)
        var revisions: [NoteRevision] = []

        init(
            title: String = "",
            body: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isPinned: Bool = false,
            eventDate: Date? = nil
        ) {
            self.title = title
            self.body = body
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
            self.eventDate = eventDate
        }
    }

    /// A folder with no way to sit inside another one.
    @Model
    final class Folder {
        var name: String
        var createdAt: Date

        @Relationship(deleteRule: .nullify, inverse: \Note.folder)
        var notes: [Note] = []

        init(name: String = "", createdAt: Date = Date()) {
            self.name = name
            self.createdAt = createdAt
        }
    }

    @Model
    final class NoteDrawing {
        @Attribute(.externalStorage)
        var data: Data

        var updatedAt: Date
        var note: Note?

        init(data: Data = Data(), updatedAt: Date = Date()) {
            self.data = data
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class NoteRevision {
        var title: String
        var body: String
        var eventDate: Date?
        var updatedAt: Date
        var capturedAt: Date
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
    }
}
