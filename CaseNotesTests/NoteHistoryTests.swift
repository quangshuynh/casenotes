//
//  NoteHistoryTests.swift
//  CaseNotesTests
//
//  Created by q on 8/28/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Covers version history: what produces a version, what deliberately does not,
/// what a version holds, and what restoring one does to the note and to the
/// rest of the history.
@MainActor
struct NoteHistoryTests {
    private let firstEdit = Date(timeIntervalSince1970: 1_700_000_100)
    private let secondEdit = Date(timeIntervalSince1970: 1_700_500_000)
    private let thirdEdit = Date(timeIntervalSince1970: 1_700_900_000)
    private let eventDate = Date(timeIntervalSince1970: 1_700_086_400)

    /// A fresh in-memory store holding every model the app registers.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A stored note holding its first saved state.
    private func makeNote(in context: ModelContext) -> Note {
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            updatedAt: firstEdit
        )
        context.insert(note)
        return note
    }

    // MARK: Creating a note

    @Test
    func newNotesStartWithNoRevisions() throws {
        let context = try makeContext()
        let note = Note()

        // The creation path applies the draft directly: there is no earlier
        // state, so recording one would invent a version that never existed.
        NoteDraft(title: "Site Visit", body: "Walked the north wing.")
            .apply(to: note, at: firstEdit)
        context.insert(note)

        #expect(note.revisions.isEmpty)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    // MARK: Saving

    @Test
    func savingAnEditPreservesTheStateItReplaces() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        note.eventDate = eventDate

        var draft = NoteDraft(note: note)
        draft.title = "Site Visit, Revised"
        draft.body = "Walked the north wing twice."
        draft.eventDate = nil

        let didChange = NoteHistory.save(
            draft,
            to: note,
            in: context,
            at: secondEdit
        )

        #expect(didChange)
        #expect(note.title == "Site Visit, Revised")
        #expect(note.body == "Walked the north wing twice.")
        #expect(note.updatedAt == secondEdit)

        let revisions = NoteHistory.revisions(of: note)
        #expect(revisions.count == 1)

        let revision = try #require(revisions.first)
        #expect(revision.title == "Site Visit")
        #expect(revision.body == "Walked the north wing.")
        #expect(revision.eventDate == eventDate)
        #expect(revision.note?.persistentModelID == note.persistentModelID)
    }

    @Test
    func aRevisionCarriesTheEditTimeOfTheStateItHoldsAndOfItsCapture() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var draft = NoteDraft(note: note)
        draft.body = "Walked the north wing twice."

        NoteHistory.save(draft, to: note, in: context, at: secondEdit)

        let revision = try #require(NoteHistory.revisions(of: note).first)

        // The version was written at the first edit and replaced at the second.
        #expect(revision.updatedAt == firstEdit)
        #expect(revision.capturedAt == secondEdit)
    }

    @Test
    func savingWithoutChangesCreatesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        let didChange = NoteHistory.save(
            NoteDraft(note: note),
            to: note,
            in: context,
            at: secondEdit
        )

        #expect(didChange == false)
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func whitespaceOnlyTitleChangesCreateNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var draft = NoteDraft(note: note)
        draft.title = "  Site Visit  "

        #expect(NoteHistory.save(draft, to: note, in: context, at: secondEdit) == false)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func abandoningAnEditCreatesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        // Cancel is the absence of a save: the draft is edited and dropped.
        var draft = NoteDraft(note: note)
        draft.body = "Discarded text."

        #expect(draft.hasContentChanges(comparedTo: note))
        #expect(note.body == "Walked the north wing.")
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func refilingANoteCreatesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        var draft = NoteDraft(note: note)
        draft.folder = folder

        let didChange = NoteHistory.save(
            draft,
            to: note,
            in: context,
            at: secondEdit
        )

        // Filing organizes a note rather than rewriting it, so it moves neither
        // the edit timestamp nor the history.
        #expect(didChange)
        #expect(note.folder?.name == "Site Visits")
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func pinningANoteCreatesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        note.isPinned.toggle()

        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func readingANoteCreatesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        _ = NoteDraft(note: note)
        _ = NoteHistory.revisions(of: note)

        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func laterEditsLeaveEarlierVersionsUntouched() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var second = NoteDraft(note: note)
        second.body = "Second version."
        NoteHistory.save(second, to: note, in: context, at: secondEdit)

        var third = NoteDraft(note: note)
        third.body = "Third version."
        NoteHistory.save(third, to: note, in: context, at: thirdEdit)

        let revisions = NoteHistory.revisions(of: note)

        #expect(revisions.count == 2)
        #expect(revisions.map(\.body) == ["Second version.", "Walked the north wing."])
        #expect(revisions.map(\.capturedAt) == [thirdEdit, secondEdit])
        #expect(note.body == "Third version.")
    }

    // MARK: Ordering

    @Test
    func revisionsReadNewestFirstWhateverOrderTheyWereStoredIn() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        // Inserted oldest last on purpose: the relationship array offers no
        // order guarantee, so the sort is what the list depends on.
        for (index, date) in [thirdEdit, firstEdit, secondEdit].enumerated() {
            let revision = NoteRevision(
                title: "Version \(index)",
                body: "Body \(index)",
                updatedAt: date,
                capturedAt: date
            )
            context.insert(revision)
            revision.note = note
        }

        let revisions = NoteHistory.revisions(of: note)

        #expect(revisions.map(\.capturedAt) == [thirdEdit, secondEdit, firstEdit])
    }

    @Test
    func revisionsCapturedAtTheSameInstantOrderDeterministically() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        for title in ["Second", "First"] {
            let revision = NoteRevision(
                title: title,
                body: "Body",
                updatedAt: secondEdit,
                capturedAt: secondEdit
            )
            context.insert(revision)
            revision.note = note
        }

        #expect(NoteHistory.revisions(of: note).map(\.title) == ["First", "Second"])
    }

    // MARK: Restoring

    @Test
    func restoringMakesAnOlderVersionCurrent() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        note.eventDate = eventDate

        var draft = NoteDraft(note: note)
        draft.title = "Site Visit, Revised"
        draft.body = "Walked the north wing twice."
        draft.eventDate = nil
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)

        let revision = try #require(NoteHistory.revisions(of: note).first)
        let didChange = NoteHistory.restore(
            revision,
            to: note,
            in: context,
            at: thirdEdit
        )

        #expect(didChange)
        #expect(note.title == "Site Visit")
        #expect(note.body == "Walked the north wing.")
        #expect(note.eventDate == eventDate)
        #expect(note.updatedAt == thirdEdit)
    }

    @Test
    func restoringKeepsTheVersionItReplacedAndEverythingOlder() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var second = NoteDraft(note: note)
        second.body = "Second version."
        NoteHistory.save(second, to: note, in: context, at: secondEdit)

        let oldest = try #require(NoteHistory.revisions(of: note).last)
        NoteHistory.restore(oldest, to: note, in: context, at: thirdEdit)

        let revisions = NoteHistory.revisions(of: note)

        // Restoring is a new state transition, not a rewind: the version that
        // was current is now recoverable, and nothing newer was discarded.
        #expect(revisions.count == 2)
        #expect(revisions.map(\.body) == ["Second version.", "Walked the north wing."])
        #expect(note.body == "Walked the north wing.")
    }

    @Test
    func restoringTheStateANoteAlreadyHasChangesNothing() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var draft = NoteDraft(note: note)
        draft.body = "Second version."
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)

        let revision = try #require(NoteHistory.revisions(of: note).first)
        NoteHistory.restore(revision, to: note, in: context, at: thirdEdit)

        // Restoring the same version again is a no-op rather than a duplicate.
        let didChange = NoteHistory.restore(
            revision,
            to: note,
            in: context,
            at: thirdEdit
        )

        #expect(didChange == false)
        #expect(NoteHistory.revisions(of: note).count == 2)
        #expect(note.updatedAt == thirdEdit)
    }

    @Test
    func restoringTextLeavesTheDrawingAlone() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        let sketch = NoteDrawing(data: Data([0x01, 0x02, 0x03]), updatedAt: firstEdit)
        context.insert(sketch)
        note.drawing = sketch

        var draft = NoteDraft(note: note)
        draft.body = "Second version."
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)

        let revision = try #require(NoteHistory.revisions(of: note).first)
        NoteHistory.restore(revision, to: note, in: context, at: thirdEdit)

        // Drawings are current-state attachments and sit outside version
        // history, so restoring text must neither revert nor remove one.
        #expect(note.drawing?.data == Data([0x01, 0x02, 0x03]))
        #expect(note.drawing?.updatedAt == firstEdit)
    }

    // MARK: Persistence

    @Test
    func revisionsPersistAndReload() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var draft = NoteDraft(note: note)
        draft.body = "Second version."
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<NoteRevision>())

        #expect(stored.count == 1)

        let revision = try #require(stored.first)
        #expect(revision.body == "Walked the north wing.")
        #expect(revision.note?.persistentModelID == note.persistentModelID)
    }

    @Test
    func deletingANoteDeletesItsHistory() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        var draft = NoteDraft(note: note)
        draft.body = "Second version."
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)
        try context.save()

        context.delete(note)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NoteRevision>()).isEmpty)
    }

    @Test
    func deletingAFolderKeepsTheHistoryOfItsNotes() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)
        note.folder = folder

        var draft = NoteDraft(note: note)
        draft.body = "Second version."
        NoteHistory.save(draft, to: note, in: context, at: secondEdit)
        try context.save()

        context.delete(folder)
        try context.save()

        // Folders nullify rather than cascade, so neither the note nor anything
        // it can recover goes with them.
        let notes = try context.fetch(FetchDescriptor<Note>())
        let survivor = try #require(notes.first)

        #expect(survivor.folder == nil)
        #expect(NoteHistory.revisions(of: survivor).count == 1)
    }
}
