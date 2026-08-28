//
//  CaseNotesTests.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

@MainActor
struct CaseNotesTests {
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
    
    @Test
    func noteDefaultsToUnpinnedWithoutEventDate() {
        let note = Note()

        #expect(note.isPinned == false)
        #expect(note.eventDate == nil)
    }

    @Test
    func draftSeedsFromExistingNote() {
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            eventDate: eventDate
        )

        let draft = NoteDraft(note: note)

        #expect(draft.title == "Site Visit")
        #expect(draft.body == "Walked the north wing.")
        #expect(draft.eventDate == eventDate)
    }

    @Test
    func draftRequiresANonEmptyTitle() {
        #expect(NoteDraft(title: "", body: "Text").isSavable == false)
        #expect(NoteDraft(title: "   \n ", body: "Text").isSavable == false)
        #expect(NoteDraft(title: "Site Visit").isSavable)
    }

    @Test
    func applyingAnUnchangedDraftLeavesTheNoteAlone() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            updatedAt: updatedAt
        )

        let didChange = NoteDraft(note: note).apply(
            to: note,
            at: Date(timeIntervalSince1970: 1_700_500_000)
        )

        #expect(didChange == false)
        #expect(note.updatedAt == updatedAt)
    }

    @Test
    func applyingAChangedDraftRewritesTheNoteAndTimestamp() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let editedAt = Date(timeIntervalSince1970: 1_700_500_000)
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            updatedAt: updatedAt
        )

        var draft = NoteDraft(note: note)
        draft.body = "Walked the north wing. Photograph the stairwell."
        draft.eventDate = eventDate

        let didChange = draft.apply(to: note, at: editedAt)

        #expect(didChange)
        #expect(note.body == "Walked the north wing. Photograph the stairwell.")
        #expect(note.eventDate == eventDate)
        #expect(note.updatedAt == editedAt)
    }

    @Test
    func applyingADraftTrimsTitleWhitespace() {
        let note = Note(title: "Site Visit")
        let draft = NoteDraft(title: "  Revised Title  ", body: note.body)

        draft.apply(to: note)

        #expect(note.title == "Revised Title")
    }

    @Test
    func titleWhitespaceAloneIsNotAChange() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let note = Note(title: "Site Visit", updatedAt: updatedAt)
        let draft = NoteDraft(title: "  Site Visit  ", body: note.body)

        #expect(draft.hasChanges(comparedTo: note) == false)
        #expect(draft.apply(to: note) == false)
        #expect(note.updatedAt == updatedAt)
    }

    @Test
    func clearingAnEventDateCountsAsAChange() {
        let note = Note(
            title: "Site Visit",
            eventDate: Date(timeIntervalSince1970: 1_700_086_400)
        )

        var draft = NoteDraft(note: note)
        draft.eventDate = nil

        #expect(draft.hasChanges(comparedTo: note))
        #expect(draft.apply(to: note))
        #expect(note.eventDate == nil)
    }

    @Test
    func draftSeedsTheNotesFolder() throws {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let note = Note(title: "North Wing", folder: folder)
        context.insert(note)

        #expect(NoteDraft(note: note).folder?.name == "Site Visits")
    }

    @Test
    func refilingANoteDoesNotChangeItsEditTimestamp() throws {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let note = Note(title: "North Wing", updatedAt: updatedAt)
        context.insert(note)

        var draft = NoteDraft(note: note)
        draft.folder = folder

        let didChange = draft.apply(
            to: note,
            at: Date(timeIntervalSince1970: 1_700_500_000)
        )

        #expect(didChange)
        #expect(note.folder?.name == "Site Visits")
        #expect(note.updatedAt == updatedAt)
    }

    @Test
    func editingContentWhileRefilingStillUpdatesTheTimestamp() throws {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let editedAt = Date(timeIntervalSince1970: 1_700_500_000)
        let note = Note(
            title: "North Wing",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        context.insert(note)

        var draft = NoteDraft(note: note)
        draft.body = "Revised."
        draft.folder = folder

        draft.apply(to: note, at: editedAt)

        #expect(note.folder?.name == "Site Visits")
        #expect(note.updatedAt == editedAt)
    }

    @Test
    func existingNoteStoresOpenAfterFoldersAreAdded() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write a store using the schema as it stood before folders existed.
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
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)
        #expect(notes.first?.title == "Legacy Note")
        #expect(notes.first?.folder == nil)
    }
}
