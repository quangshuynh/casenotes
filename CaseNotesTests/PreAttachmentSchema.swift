//
//  PreAttachmentSchema.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import SwiftData

/// The models exactly as they stood before notes could carry files.
///
/// A migration test needs a store whose `Note` entity genuinely has no
/// attachments relationship and which holds no attachment entity at all. The
/// current model cannot write one, and naming fewer models does not help,
/// because SwiftData resolves a schema through relationships and registers
/// every entity it can reach.
///
/// These declarations are therefore the only way to write the older store.
/// Entity names come from the class names, which are the same as the app's, so a
/// store written here is the same store the previous build would have left
/// behind. Nothing in the app refers to these types, and they must not gain
/// properties: their whole purpose is to stay frozen at the pre-attachment
/// schema.
///
/// The earlier freezes in ``PreRevisionSchema`` and ``PreNestedFolderSchema``
/// cover different points in the history and are left alone.
enum PreAttachmentSchema {
    /// Every model registered by the build before attachments existed.
    static let models: [any PersistentModel.Type] = [
        Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
    ]

    /// A note with no way to carry a file.
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

    @Model
    final class Folder {
        var name: String
        var createdAt: Date

        @Relationship(deleteRule: .nullify, inverse: \Note.folder)
        var notes: [Note] = []

        var parent: Folder?

        @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
        var children: [Folder] = []

        init(name: String = "", createdAt: Date = Date(), parent: Folder? = nil) {
            self.name = name
            self.createdAt = createdAt
            self.parent = parent
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
