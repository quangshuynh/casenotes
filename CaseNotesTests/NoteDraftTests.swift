//
//  NoteDraftTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Covers the editing contract: what counts as a change, what Cancel discards,
/// and when a note's edit timestamp is allowed to move.
@MainActor
struct NoteDraftTests {
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
    func draftsAreEqualOnlyWhenEveryFieldMatches() {
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)
        let draft = NoteDraft(
            title: "North Wing",
            body: "Walked the wing.",
            eventDate: eventDate
        )

        #expect(draft == NoteDraft(
            title: "North Wing",
            body: "Walked the wing.",
            eventDate: eventDate
        ))

        var edited = draft
        edited.body = "Walked the wing twice."
        #expect(edited != draft)

        var redated = draft
        redated.eventDate = nil
        #expect(redated != draft)
    }

    @Test
    func changingOnlyTheFolderMakesADraftUnequal() throws {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let draft = NoteDraft(title: "North Wing")
        var refiled = draft
        refiled.folder = folder

        // Equality is what the editor uses to decide whether closing needs a
        // discard confirmation, so refiling has to register as a change.
        #expect(refiled != draft)
    }
}
