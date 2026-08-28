//
//  NoteTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Covers the note model itself: its defaults, what it stores, and how it
/// survives in a SwiftData store across schema changes.
@MainActor
struct NoteTests {
    @Test
    func noteInitializerStoresValues() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)

        let note = Note(
            title: "Meeting Notes",
            body: "Follow up on the project timeline.",
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: true,
            eventDate: eventDate
        )

        #expect(note.title == "Meeting Notes")
        #expect(note.body == "Follow up on the project timeline.")
        #expect(note.createdAt == createdAt)
        #expect(note.updatedAt == updatedAt)
        #expect(note.isPinned)
        #expect(note.eventDate == eventDate)
    }

    @Test
    func noteDefaultsToUnpinnedWithoutEventDate() {
        let note = Note()

        #expect(note.isPinned == false)
        #expect(note.eventDate == nil)
    }

    @Test
    func notePersistsInMemoryModelContainer() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)
        
        let note = Note(
            title: "Project Ideas",
            body: "Explore a small native iOS app.",
            isPinned: true,
            eventDate: eventDate
        )

        context.insert(note)
        try context.save()

        let fetchedNotes = try context.fetch(FetchDescriptor<Note>())

        #expect(fetchedNotes.count == 1)
        
        let fetchedNote = try #require(fetchedNotes.first)
        #expect(fetchedNote.title == "Project Ideas")
        #expect(fetchedNote.body == "Explore a small native iOS app.")
        #expect(fetchedNote.isPinned)
        #expect(fetchedNote.eventDate == eventDate)
    }

    /// An on-disk store written with only notes in it reopens under the model
    /// list a shipped build registers, with its notes intact and the entities it
    /// never held simply empty.
    ///
    /// Naming fewer models does not by itself produce an older schema, since
    /// SwiftData registers every entity reachable through a relationship, so the
    /// file here is written with the current one. Reopening a store that
    /// genuinely predates an entity is covered by
    /// ``existingNoteStoresOpenAfterVersionHistoryIsAdded()``.
    @Test
    func existingNoteStoresOpenAfterFoldersAndDrawingsAreAdded() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write a store holding nothing but a note.
        do {
            let container = try ModelContainer(
                for: Note.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            context.insert(
                Note(title: "Legacy Note", body: "Written before folders existed.")
            )
            try context.save()
        }

        // Reopen the same file with the current schema.
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)

        let note = try #require(notes.first)
        #expect(note.title == "Legacy Note")
        #expect(note.body == "Written before folders existed.")
        #expect(note.folder == nil)
        #expect(note.drawing == nil)

        // The entities the store never held come back empty rather than
        // failing to open.
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let drawings = try context.fetch(FetchDescriptor<NoteDrawing>())

        #expect(folders.isEmpty)
        #expect(drawings.isEmpty)
    }

    /// Version history was added the same way folders and drawings were: a new
    /// entity plus a cascading relationship, which SwiftData migrates
    /// automatically without a migration plan.
    ///
    /// The older store is written through ``PreRevisionSchema``, which declares
    /// the models as they stood before revisions existed, so the file genuinely
    /// has no revision entity in it. Everything a user had keeps working, and
    /// the note simply starts out with no history.
    @Test
    func existingNoteStoresOpenAfterVersionHistoryIsAdded() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-revisions-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let writtenAt = Date(timeIntervalSince1970: 1_700_000_100)

        // Write a store using the schema as it stood before version history.
        do {
            let container = try ModelContainer(
                for: Schema(PreRevisionSchema.models),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let folder = PreRevisionSchema.Folder(name: "Site Visits")
            let drawing = PreRevisionSchema.NoteDrawing(
                data: Data([0x01, 0x02, 0x03]),
                updatedAt: writtenAt
            )
            let note = PreRevisionSchema.Note(
                title: "Legacy Note",
                body: "Written before version history existed.",
                updatedAt: writtenAt
            )

            context.insert(folder)
            context.insert(drawing)
            context.insert(note)
            note.folder = folder
            note.drawing = drawing
            try context.save()
        }

        // Reopen the same file with the model list the app registers.
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)

        let note = try #require(notes.first)
        #expect(note.title == "Legacy Note")
        #expect(note.body == "Written before version history existed.")
        #expect(note.updatedAt == writtenAt)
        #expect(note.folder?.name == "Site Visits")
        #expect(note.drawing?.data == Data([0x01, 0x02, 0x03]))

        // The note keeps everything it had and simply starts with no history.
        #expect(note.revisions.isEmpty)
        #expect(NoteHistory.revisions(of: note).isEmpty)

        let revisions = try context.fetch(FetchDescriptor<NoteRevision>())
        #expect(revisions.isEmpty)
    }
}
