//
//  PreRevisionSchema.swift
//  CaseNotesTests
//
//  Created by q on 8/28/26.
//

import Foundation
import SwiftData

/// The models exactly as they stood before version history existed.
///
/// A migration test needs a store that genuinely lacks the revision entity, and
/// naming a subset of the app's models cannot produce one: SwiftData resolves a
/// schema through relationships, so asking for `Note` alone still registers
/// every entity it can reach. These declarations are therefore the only way to
/// write the older store.
///
/// Entity names come from the class names, which are the same as the app's, so a
/// store written here is the same store an older build would have left behind.
/// Nothing in the app refers to these types, and they must not gain properties:
/// their whole purpose is to stay frozen at the previous schema.
enum PreRevisionSchema {
    /// Every model registered by the build before version history.
    static let models: [any PersistentModel.Type] = [
        Note.self, Folder.self, NoteDrawing.self,
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
}
