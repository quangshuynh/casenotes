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

    /// Nested folders changed an existing entity rather than adding one: a
    /// folder gained a parent and a children relationship. That is still an
    /// additive change SwiftData migrates automatically, and this proves it
    /// against a store that genuinely predates the self-relation.
    ///
    /// The older store is written through ``PreNestedFolderSchema``, whose
    /// `Folder` has no way to sit inside another. Writing it with today's
    /// `Folder` would produce the new schema and prove nothing.
    ///
    /// Everything a user had keeps working: folders survive as root folders,
    /// filing survives exactly, unfiled notes stay unfiled, and drawings and
    /// revisions come across untouched.
    @Test
    func existingNoteStoresOpenAfterFoldersCanNest() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-nesting-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let writtenAt = Date(timeIntervalSince1970: 1_700_000_100)
        let createdAt = Date(timeIntervalSince1970: 1_699_000_000)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let drawingBytes = Data([0x0A, 0x0B, 0x0C])

        // Write a store using the schema as it stood while folders were flat.
        do {
            let container = try ModelContainer(
                for: Schema(PreNestedFolderSchema.models),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let siteVisits = PreNestedFolderSchema.Folder(name: "Site Visits")
            let research = PreNestedFolderSchema.Folder(name: "Research")
            let empty = PreNestedFolderSchema.Folder(name: "Archive")
            context.insert(siteVisits)
            context.insert(research)
            context.insert(empty)

            let filed = PreNestedFolderSchema.Note(
                title: "North Wing",
                body: "Walked the north wing.",
                createdAt: createdAt,
                updatedAt: writtenAt
            )
            let deeper = PreNestedFolderSchema.Note(
                title: "Reading List",
                body: "Sources to follow up.",
                createdAt: createdAt,
                updatedAt: writtenAt
            )
            let loose = PreNestedFolderSchema.Note(
                title: "Stray Thought",
                body: "Never filed anywhere.",
                createdAt: createdAt,
                updatedAt: writtenAt
            )
            context.insert(filed)
            context.insert(deeper)
            context.insert(loose)
            filed.folder = siteVisits
            deeper.folder = research

            let drawing = PreNestedFolderSchema.NoteDrawing(
                data: drawingBytes,
                updatedAt: writtenAt
            )
            context.insert(drawing)
            filed.drawing = drawing

            let revision = PreNestedFolderSchema.NoteRevision(
                title: "North Wing",
                body: "An earlier draft.",
                updatedAt: createdAt,
                capturedAt: capturedAt
            )
            context.insert(revision)
            revision.note = filed

            try context.save()
        }

        // Reopen the same file with the model list the app registers.
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let folders = try context.fetch(
            FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
        )
        let notes = try context.fetch(
            FetchDescriptor<Note>(sortBy: [SortDescriptor(\.title)])
        )

        // Every folder that existed survives, and every one of them is a root
        // folder, because a flat store had nowhere else for them to be.
        #expect(folders.map(\.name) == ["Archive", "Research", "Site Visits"])
        #expect(folders.allSatisfy { $0.isRoot })
        #expect(folders.allSatisfy { $0.parent == nil })
        #expect(folders.allSatisfy { $0.children.isEmpty })

        // The hierarchy starts out cycle free and reads as a flat top level.
        for folder in folders {
            #expect(FolderHierarchy.ancestors(of: folder).isEmpty)
            #expect(FolderHierarchy.descendants(of: folder).isEmpty)
            #expect(FolderHierarchy.pathComponents(of: folder) == [folder.displayName])
        }

        #expect(FolderTree(folders).roots.count == 3)

        // Filing survives exactly as it was.
        #expect(notes.map(\.title) == ["North Wing", "Reading List", "Stray Thought"])

        let filed = try #require(notes.first { $0.title == "North Wing" })
        let deeper = try #require(notes.first { $0.title == "Reading List" })
        let loose = try #require(notes.first { $0.title == "Stray Thought" })

        #expect(filed.folder?.name == "Site Visits")
        #expect(deeper.folder?.name == "Research")
        #expect(loose.folder == nil)

        // Authored content and timestamps are untouched by the upgrade.
        #expect(filed.body == "Walked the north wing.")
        #expect(filed.createdAt == createdAt)
        #expect(filed.updatedAt == writtenAt)
        #expect(loose.updatedAt == writtenAt)

        // Drawings and history come across with the notes that own them.
        #expect(filed.drawing?.data == drawingBytes)
        #expect(filed.drawing?.updatedAt == writtenAt)

        let history = NoteHistory.revisions(of: filed)
        #expect(history.count == 1)
        #expect(history.first?.body == "An earlier draft.")
        #expect(history.first?.capturedAt == capturedAt)
        #expect(deeper.revisions.isEmpty)

        let drawings = try context.fetch(FetchDescriptor<NoteDrawing>())
        let revisions = try context.fetch(FetchDescriptor<NoteRevision>())

        #expect(drawings.count == 1)
        #expect(revisions.count == 1)
    }
}
