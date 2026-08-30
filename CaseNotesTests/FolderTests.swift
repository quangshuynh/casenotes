//
//  FolderTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

@MainActor
struct FolderTests {
    /// A fresh in-memory store holding both models.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test
    func notesDefaultToUnfiled() {
        #expect(Note().folder == nil)
    }

    @Test
    func filingANotePopulatesBothSidesOfTheRelationship() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        let note = Note(title: "North Wing")

        context.insert(folder)
        context.insert(note)
        note.folder = folder
        try context.save()

        #expect(note.folder?.name == "Site Visits")
        #expect(folder.notes.count == 1)
        #expect(folder.notes.first?.title == "North Wing")
    }

    @Test
    func foldersPersistAndRefetch() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)
        context.insert(Note(title: "North Wing", folder: folder))
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let fetched = try #require(folders.first)

        #expect(folders.count == 1)
        #expect(fetched.name == "Site Visits")
        #expect(fetched.notes.count == 1)
    }

    @Test
    func deletingAFolderKeepsItsNotesAndUnfilesThem() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let filed = Note(title: "North Wing", folder: folder)
        let unfiled = Note(title: "Reading List")
        context.insert(filed)
        context.insert(unfiled)
        try context.save()

        context.delete(folder)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        let folders = try context.fetch(FetchDescriptor<Folder>())

        #expect(folders.isEmpty)
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.folder == nil })
        #expect(notes.contains { $0.title == "North Wing" })
    }

    @Test
    func deletingANoteLeavesItsFolderIntact() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let note = Note(title: "North Wing", folder: folder)
        context.insert(note)
        try context.save()

        context.delete(note)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())

        #expect(folders.count == 1)
        #expect(folders.first?.notes.isEmpty == true)
    }

    @Test
    func notesMoveBetweenFolders() throws {
        let context = try makeContext()
        let source = Folder(name: "Inbox")
        let destination = Folder(name: "Archive")
        context.insert(source)
        context.insert(destination)

        let note = Note(title: "North Wing", folder: source)
        context.insert(note)
        try context.save()

        note.folder = destination
        try context.save()

        #expect(source.notes.isEmpty)
        #expect(destination.notes.count == 1)
        #expect(note.folder?.name == "Archive")
    }

    @Test
    func aNoteCanBeUnfiledWithoutBeingDeleted() throws {
        let context = try makeContext()
        let folder = Folder(name: "Inbox")
        context.insert(folder)

        let note = Note(title: "North Wing", folder: folder)
        context.insert(note)
        try context.save()

        note.folder = nil
        try context.save()

        #expect(folder.notes.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    @Test
    func renamingAFolderKeepsItsNotes() throws {
        let context = try makeContext()
        let folder = Folder(name: "Inbox")
        context.insert(folder)
        context.insert(Note(title: "North Wing", folder: folder))
        try context.save()

        folder.name = "Site Visits"
        try context.save()

        #expect(folder.notes.count == 1)
        #expect(folder.displayName == "Site Visits")
    }

    @Test
    func unnamedFoldersFallBackToAPlaceholder() {
        #expect(Folder(name: "   ").displayName == "Untitled Folder")
        #expect(Folder(name: "Inbox").displayName == "Inbox")
    }

    // MARK: Nesting

    @Test
    func aFolderWithoutAParentIsARootFolder() {
        let folder = Folder(name: "Work")

        #expect(folder.parent == nil)
        #expect(folder.isRoot)
        #expect(folder.children.isEmpty)
    }

    /// The self-relation is declared on one side and read from both, so filing
    /// a folder inside another is enough to make it appear as a child.
    @Test
    func filingAFolderPopulatesBothSidesOfTheRelationship() throws {
        let context = try makeContext()
        let work = Folder(name: "Work")
        let alpha = Folder(name: "Project Alpha")
        context.insert(work)
        context.insert(alpha)
        alpha.parent = work
        try context.save()

        #expect(alpha.parent?.name == "Work")
        #expect(alpha.isRoot == false)
        #expect(work.children.map(\.name) == ["Project Alpha"])
        #expect(work.isRoot)
    }

    @Test
    func aFolderCanBeCreatedInsideAnotherInOneStep() throws {
        let context = try makeContext()
        let work = Folder(name: "Work")
        context.insert(work)

        let alpha = Folder(name: "Project Alpha", parent: work)
        context.insert(alpha)
        try context.save()

        #expect(work.children.map(\.name) == ["Project Alpha"])
    }

    /// A tree written to a file comes back as the same tree, which is the
    /// claim the store itself has to support rather than the object graph.
    @Test
    func aFolderTreeSurvivesSavingAndReopening() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-hierarchy-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)

            let work = Folder(name: "Work")
            let alpha = Folder(name: "Project Alpha", parent: work)
            let research = Folder(name: "Research", parent: alpha)
            context.insert(work)
            context.insert(alpha)
            context.insert(research)
            context.insert(Note(title: "Interview", folder: research))
            try context.save()
        }

        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let folders = try context.fetch(
            FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
        )

        #expect(folders.map(\.name) == ["Project Alpha", "Research", "Work"])

        let research = try #require(folders.first { $0.name == "Research" })
        let work = try #require(folders.first { $0.name == "Work" })

        #expect(FolderHierarchy.pathComponents(of: research) == ["Work", "Project Alpha", "Research"])
        #expect(work.isRoot)
        #expect(work.children.map(\.name) == ["Project Alpha"])
        #expect(research.notes.map(\.title) == ["Interview"])
    }

    @Test
    func movingAFolderBetweenParentsPersists() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-move-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = ModelConfiguration(url: url)

        do {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
                configurations: configuration
            )
            let context = ModelContext(container)

            let work = Folder(name: "Work")
            let personal = Folder(name: "Personal")
            let journal = Folder(name: "Journal", parent: work)
            context.insert(work)
            context.insert(personal)
            context.insert(journal)
            try context.save()

            FolderHierarchy.move(journal, to: personal)
            try context.save()
        }

        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let journal = try #require(folders.first { $0.name == "Journal" })

        #expect(journal.parent?.name == "Personal")
    }

    @Test
    func movingAFolderBackToRootPersists() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-root-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = ModelConfiguration(url: url)

        do {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
                configurations: configuration
            )
            let context = ModelContext(container)

            let work = Folder(name: "Work")
            let journal = Folder(name: "Journal", parent: work)
            context.insert(work)
            context.insert(journal)
            try context.save()

            FolderHierarchy.move(journal, to: nil)
            try context.save()
        }

        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let journal = try #require(folders.first { $0.name == "Journal" })
        let work = try #require(folders.first { $0.name == "Work" })

        #expect(journal.isRoot)
        #expect(work.children.isEmpty)
    }

    /// Deleting a folder must not take its subfolders with it even when the
    /// promotion step is skipped, so the relationship's own rule is checked
    /// rather than assumed.
    @Test
    func theChildRelationshipNullifiesRatherThanCascades() throws {
        let context = try makeContext()
        let work = Folder(name: "Work")
        let alpha = Folder(name: "Project Alpha", parent: work)
        context.insert(work)
        context.insert(alpha)
        try context.save()

        context.delete(work)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())

        #expect(folders.map(\.name) == ["Project Alpha"])
        #expect(alpha.parent == nil)
    }
}
