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
}
