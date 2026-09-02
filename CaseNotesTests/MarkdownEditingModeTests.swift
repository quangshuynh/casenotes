//
//  MarkdownEditingModeTests.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Covers the three Markdown modes and the promise that runs through all of
/// them: they change what the editor shows and nothing else.
///
/// The mode itself is view state with no route to the store, so the tests that
/// matter are about the draft. They drive the same writes live preview performs,
/// and then check the note, its edit timestamp, and its history against the
/// rules that were already in place before live preview existed.
@MainActor
struct MarkdownEditingModeTests {
    private let firstEdit = Date(timeIntervalSince1970: 1_700_000_100)
    private let secondEdit = Date(timeIntervalSince1970: 1_700_500_000)

    private let body = """
        # Site Visit

        Walked the **north wing** with facilities.

        - Photograph the stairwell
        - Check the ramp handrail
        """

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeNote(in context: ModelContext) -> Note {
        let note = Note(title: "Site Visit", body: body, updatedAt: firstEdit)
        context.insert(note)
        return note
    }

    /// Rewrites one region of a body the way live preview writes an edit back.
    ///
    /// - Parameters:
    ///   - source: The body being edited.
    ///   - index: Which region the caret is in.
    ///   - text: The region's new source.
    /// - Returns: The rewritten body.
    private func editRegion(_ index: Int, of source: String, to text: String) -> String {
        let map = MarkdownSourceMap(source)

        guard let region = map.region(id: index) else {
            Issue.record("Fixture has no region \(index)")
            return source
        }

        return MarkdownSourceMap.replacing(source, utf16Range: region.utf16Range, with: text)
    }

    // MARK: The modes themselves

    @Test
    func theEditorOpensInLivePreview() {
        #expect(MarkdownEditingMode.default == .livePreview)
    }

    @Test
    func onlyReadingRefusesEditing() {
        #expect(!MarkdownEditingMode.reading.isEditable)
        #expect(MarkdownEditingMode.livePreview.isEditable)
        #expect(MarkdownEditingMode.source.isEditable)
    }

    @Test
    func everyModeIsNamedSymbolledAndDescribedDistinctly() {
        let modes = MarkdownEditingMode.allCases

        #expect(modes.count == 3)
        #expect(Set(modes.map(\.title)).count == modes.count)
        #expect(Set(modes.map(\.symbolName)).count == modes.count)
        #expect(Set(modes.map(\.summary)).count == modes.count)
        #expect(Set(modes.map(\.footer)).count == modes.count)
        #expect(Set(modes.map(\.id)).count == modes.count)
        #expect(modes.allSatisfy { !$0.title.isEmpty && !$0.symbolName.isEmpty })
    }

    // MARK: Switching modes

    @Test
    func switchingBetweenModesLeavesTheDraftBodyByteForByteIdentical() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        let draft = NoteDraft(note: note)

        // Reading renders the draft, live preview divides it, and source shows
        // it whole. None of them writes, so a tour of all three is a no-op.
        for mode in MarkdownEditingMode.allCases {
            _ = MarkdownDocument(draft.body)

            if mode == .livePreview {
                let map = MarkdownSourceMap(draft.body)
                #expect(map.regions.map(map.text(of:)).joined() == draft.body)
            }
        }

        #expect(draft.body == body)
        #expect(draft == NoteDraft(note: note))

        draft.apply(to: note, at: secondEdit)

        #expect(note.body == body)
        #expect(note.updatedAt == firstEdit)
    }

    @Test
    func switchingModesMovesNoTimestampAndWritesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)

        // Opening the editor and touring the modes produces a draft equal to
        // the note, and saving one of those changes nothing at all.
        let draft = NoteDraft(note: note)
        let changed = NoteHistory.save(draft, to: note, in: context, at: secondEdit)

        #expect(!changed)
        #expect(note.updatedAt == firstEdit)
        #expect(note.body == body)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    // MARK: Live preview editing

    @Test
    func livePreviewTypingChangesTheDraftAndNotTheNote() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        var draft = NoteDraft(note: note)

        draft.body = editRegion(1, of: draft.body, to: "Walked the **north wing** with the site manager.\n\n")
        draft.body = editRegion(0, of: draft.body, to: "# Site Visit, Tuesday\n\n")

        #expect(draft.body.contains("site manager"))
        #expect(draft.body.contains("# Site Visit, Tuesday"))

        // Nothing has been saved, so the stored note is exactly as it was.
        #expect(note.body == body)
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func cancellingAfterLivePreviewEditsLeavesTheStoredNoteUntouched() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        var draft = NoteDraft(note: note)

        draft.body = editRegion(1, of: draft.body, to: "Discarded sentence.\n\n")

        #expect(draft != NoteDraft(note: note))

        // Cancel drops the draft without applying it, which is the whole point
        // of editing a value rather than the model.
        #expect(note.body == body)
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func savingAfterLivePreviewEditsKeepsTheExistingHistoryAndTimestampRules() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        var draft = NoteDraft(note: note)

        draft.body = editRegion(1, of: draft.body, to: "Walked the **north wing** with the site manager.\n\n")

        let changed = NoteHistory.save(draft, to: note, in: context, at: secondEdit)
        let revisions = NoteHistory.revisions(of: note)

        #expect(changed)
        #expect(note.updatedAt == secondEdit)
        #expect(note.body.contains("site manager"))
        #expect(revisions.count == 1)
        #expect(revisions[0].body == body)
        #expect(revisions[0].updatedAt == firstEdit)
    }

    @Test
    func aRegionEditedBackToItsOwnTextIsNotAnEdit() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        var draft = NoteDraft(note: note)

        let map = MarkdownSourceMap(draft.body)

        for region in map.regions {
            draft.body = MarkdownSourceMap.replacing(
                draft.body,
                utf16Range: region.utf16Range,
                with: map.text(of: region)
            )
        }

        #expect(draft.body == body)
        #expect(!NoteHistory.save(draft, to: note, in: context, at: secondEdit))
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }

    @Test
    func aLivePreviewEditThatOnlyMovesFilingStillWritesNoRevision() throws {
        let context = try makeContext()
        let note = makeNote(in: context)
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        var draft = NoteDraft(note: note)
        draft.folder = folder

        #expect(NoteHistory.save(draft, to: note, in: context, at: secondEdit))
        #expect(note.folder === folder)
        #expect(note.updatedAt == firstEdit)
        #expect(NoteHistory.revisions(of: note).isEmpty)
    }
}
