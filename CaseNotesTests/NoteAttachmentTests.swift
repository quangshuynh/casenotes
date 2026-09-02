//
//  NoteAttachmentTests.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// What a save, a cancel, and a delete do to a note's attached files.
///
/// Every case runs against an in-memory store and a file store rooted in its
/// own temporary directory, so nothing here touches the real container.
@MainActor
struct NoteAttachmentTests {
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let editedAt = Date(timeIntervalSince1970: 1_700_009_000)

    /// A context, a file store, and the directory both are thrown away with.
    private struct Fixture {
        let context: ModelContext
        let root: URL
        let store: AttachmentStore

        init() throws {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
                NoteAttachment.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)

            root = URL.temporaryDirectory
                .appending(path: "casenotes-note-attachments-\(UUID().uuidString)")
            store = AttachmentStore(
                containerDirectory: root.appending(path: "container"),
                stagingParentDirectory: root.appending(path: "staging")
            )
        }

        /// Stages a synthetic document as though the user had imported one.
        ///
        /// - Parameter name: The file name the attachment carries.
        /// - Returns: The staged file, ready to put in a draft.
        func stage(_ name: String) throws -> StagedAttachment {
            let directory = root.appending(path: "sources")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let url = directory.appending(path: "\(UUID().uuidString)-\(name)")
            try Data(repeating: 0x41, count: 96).write(to: url)

            // The picker hands over whatever name the user's file has, which is
            // the name the attachment keeps.
            let renamed = directory.appending(path: name)
            try? FileManager.default.removeItem(at: renamed)
            try FileManager.default.moveItem(at: url, to: renamed)

            return try store.stage(contentsOf: renamed)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeNote(in fixture: Fixture, at date: Date) -> Note {
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            createdAt: date,
            updatedAt: date
        )
        fixture.context.insert(note)

        return note
    }

    private func exists(_ fixture: Fixture, _ attachment: NoteAttachment) -> Bool {
        fixture.store.storedFileExists(named: attachment.storedFilename)
    }

    // MARK: Saving

    @Test
    func savingKeepsTheMetadataAndTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        let staged = try fixture.stage("site-plan.pdf")

        let changed = NoteAttachments.apply(
            [DraftAttachment(staged: staged)],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(changed)

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        #expect(attachment.originalFilename == "site-plan.pdf")
        #expect(attachment.byteCount == 96)
        #expect(attachment.createdAt == editedAt)
        #expect(attachment.note?.persistentModelID == note.persistentModelID)
        #expect(exists(fixture, attachment))

        // The staged copy has moved rather than been duplicated.
        #expect(!FileManager.default.fileExists(atPath: staged.url.path(percentEncoded: false)))
    }

    @Test
    func savingAnAttachmentMovesTheEditTimestamp() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)

        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(note.updatedAt == editedAt)
    }

    @Test
    func removingAnAttachmentMovesTheEditTimestampAndDeletesTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        let storedFilename = attachment.storedFilename

        let changed = NoteAttachments.apply(
            [],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(changed)
        #expect(note.attachments.isEmpty)
        #expect(note.updatedAt == editedAt)
        #expect(!fixture.store.storedFileExists(named: storedFilename))

        let records = try fixture.context.fetch(FetchDescriptor<NoteAttachment>())
        #expect(records.isEmpty)
    }

    /// A removal has to reach the store before the bytes are thrown away. The
    /// two cannot be one transaction, and the order decides what an
    /// interruption leaves behind: a file nothing points at, which is
    /// invisible, or a record pointing at nothing, which the note has to show
    /// as an attachment it cannot open.
    ///
    /// Reopening the file is the evidence. The removal is visible in a store
    /// read from disk without anything else having asked for a save.
    @Test
    func removingAnAttachmentReachesTheStoreBeforeItsFileIsDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )

        let url = fixture.root.appending(path: "ordering.store")
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            NoteAttachment.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)

        let note = Note(title: "Site Visit", createdAt: savedAt, updatedAt: savedAt)
        context.insert(note)

        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: context,
            using: fixture.store,
            at: savedAt
        )
        try context.save()

        let storedFilename = try #require(
            NoteAttachments.attachments(of: note).first?.storedFilename
        )
        #expect(fixture.store.storedFileExists(named: storedFilename))

        NoteAttachments.apply(
            [],
            to: note,
            in: context,
            using: fixture.store,
            at: editedAt
        )

        // Read the file back through a separate context, without saving again.
        let reopened = ModelContext(container)
        let records = try reopened.fetch(FetchDescriptor<NoteAttachment>())

        #expect(records.isEmpty)
        #expect(!fixture.store.storedFileExists(named: storedFilename))
    }

    /// Saving a note whose attachment list is unchanged must leave the note
    /// exactly as it was, or every save would look like an edit.
    @Test
    func savingWithNoAttachmentChangeLeavesTheTimestampAlone() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let unchanged = NoteAttachments.draftAttachments(of: note)
        let changed = NoteAttachments.apply(
            unchanged,
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(!changed)
        #expect(note.updatedAt == savedAt)
        #expect(note.attachments.count == 1)
    }

    /// Attaching a file is a change to the note, not to its writing. History
    /// stays text only.
    @Test
    func anAttachmentOnlySaveWritesNoRevision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        var draft = NoteDraft(note: note)
        draft.attachments.append(DraftAttachment(staged: try fixture.stage("site-plan.pdf")))

        NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt)
        NoteAttachments.apply(
            draft.attachments,
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(note.revisions.isEmpty)
        #expect(NoteHistory.revisions(of: note).isEmpty)
        #expect(note.attachments.count == 1)
        #expect(note.updatedAt == editedAt)
    }

    /// Removing one is the same kind of change, and records nothing either.
    @Test
    func removingAnAttachmentWritesNoRevision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        var draft = NoteDraft(note: note)
        draft.attachments.removeAll()

        NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt)
        NoteAttachments.apply(
            draft.attachments,
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(note.revisions.isEmpty)
        #expect(note.attachments.isEmpty)
    }

    /// Editing the text still records a version, and the note's files are not
    /// disturbed by it.
    @Test
    func editingTextKeepsAVersionAndLeavesAttachmentsAlone() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)

        var draft = NoteDraft(note: note)
        draft.body = "Rewritten."

        NoteHistory.save(draft, to: note, in: fixture.context, at: editedAt)
        let changed = NoteAttachments.apply(
            draft.attachments,
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        #expect(!changed)
        #expect(NoteHistory.revisions(of: note).count == 1)
        #expect(note.attachments.count == 1)
        #expect(exists(fixture, attachment))
    }

    // MARK: Cancelling

    /// The whole point of staging: an import that is abandoned leaves nothing
    /// on the note and nothing on disk.
    @Test
    func cancellingDiscardsANewlyStagedAttachment() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        var draft = NoteDraft(note: note)
        let staged = try fixture.stage("site-plan.pdf")
        draft.attachments.append(DraftAttachment(staged: staged))

        NoteAttachments.discardStaged(draft.attachments, using: fixture.store)

        #expect(note.attachments.isEmpty)
        #expect(note.updatedAt == savedAt)
        #expect(!FileManager.default.fileExists(atPath: staged.url.path(percentEncoded: false)))

        let records = try fixture.context.fetch(FetchDescriptor<NoteAttachment>())
        #expect(records.isEmpty)
    }

    /// Removing a saved attachment is a decision the editor holds, so
    /// abandoning the edit has to put it back.
    @Test
    func cancellingKeepsAnAttachmentThatTheEditHadMarkedForRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)

        var draft = NoteDraft(note: note)
        draft.attachments.removeAll()

        // Cancel: the draft is thrown away without ever being applied.
        NoteAttachments.discardStaged(draft.attachments, using: fixture.store)

        #expect(note.attachments.count == 1)
        #expect(note.updatedAt == savedAt)
        #expect(exists(fixture, attachment))
    }

    /// A note that was never saved must not leave its imports behind either.
    @Test
    func cancellingANewNoteLeavesNoNoteAndNoFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var draft = NoteDraft(title: "Unsaved")
        let staged = try fixture.stage("site-plan.pdf")
        draft.attachments.append(DraftAttachment(staged: staged))

        NoteAttachments.discardStaged(draft.attachments, using: fixture.store)

        let notes = try fixture.context.fetch(FetchDescriptor<Note>())
        let records = try fixture.context.fetch(FetchDescriptor<NoteAttachment>())

        #expect(notes.isEmpty)
        #expect(records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.url.path(percentEncoded: false)))
    }

    // MARK: Creating

    /// Creation is one path, so a note started anywhere saves its files the
    /// same way, and a brand new note's dates all agree.
    @Test
    func creatingANoteSavesTheFilesItWasComposedWith() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var draft = NoteDraft(title: "Site Visit", body: "Walked the north wing.")
        draft.attachments.append(DraftAttachment(staged: try fixture.stage("site-plan.pdf")))

        let note = draft.insertNote(into: fixture.context, at: savedAt, using: fixture.store)
        let attachment = try #require(NoteAttachments.attachments(of: note).first)

        #expect(note.createdAt == savedAt)
        #expect(note.updatedAt == savedAt)
        #expect(note.revisions.isEmpty)
        #expect(attachment.originalFilename == "site-plan.pdf")
        #expect(exists(fixture, attachment))
    }

    // MARK: Coexistence and order

    /// Two documents that arrived under the same name are two attachments, and
    /// neither overwrites the other.
    @Test
    func twoAttachmentsNamedAlikeCoexist() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)

        NoteAttachments.apply(
            [
                DraftAttachment(staged: try fixture.stage("site-plan.pdf")),
                DraftAttachment(staged: try fixture.stage("site-plan.pdf")),
            ],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachments = NoteAttachments.attachments(of: note)

        #expect(attachments.count == 2)
        #expect(attachments.allSatisfy { $0.originalFilename == "site-plan.pdf" })
        #expect(Set(attachments.map(\.storedFilename)).count == 2)
        #expect(attachments.allSatisfy { exists(fixture, $0) })
    }

    /// Relationship arrays have no order, so the order the interface shows is
    /// established here and is stable across reads.
    @Test
    func attachmentsReadOldestFirstAndInAStableOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)

        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("first.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )
        NoteAttachments.apply(
            NoteAttachments.draftAttachments(of: note)
                + [DraftAttachment(staged: try fixture.stage("second.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: editedAt
        )

        let names = NoteAttachments.attachments(of: note).map(\.originalFilename)

        #expect(names == ["first.pdf", "second.pdf"])
        #expect(NoteAttachments.attachments(of: note).map(\.originalFilename) == names)
    }

    // MARK: Deleting

    @Test
    func deletingANoteRemovesItsRecordsAndItsFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [
                DraftAttachment(staged: try fixture.stage("site-plan.pdf")),
                DraftAttachment(staged: try fixture.stage("mitigation.docx")),
            ],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let storedNames = NoteAttachments.attachments(of: note).map(\.storedFilename)
        #expect(storedNames.count == 2)

        NoteAttachments.delete(note, in: fixture.context, using: fixture.store)
        try fixture.context.save()

        let notes = try fixture.context.fetch(FetchDescriptor<Note>())
        let records = try fixture.context.fetch(FetchDescriptor<NoteAttachment>())

        #expect(notes.isEmpty)
        #expect(records.isEmpty)
        #expect(storedNames.allSatisfy { !fixture.store.storedFileExists(named: $0) })
    }

    /// Deleting a folder deletes no notes, so it must reach no attachment
    /// either.
    @Test
    func deletingAFolderLeavesAFiledNotesAttachmentsAlone() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let folder = Folder(name: "Site Visits")
        fixture.context.insert(folder)

        let note = makeNote(in: fixture, at: savedAt)
        note.folder = folder

        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)

        FolderHierarchy.delete(folder, in: fixture.context)
        try fixture.context.save()

        #expect(note.folder == nil)
        #expect(note.updatedAt == savedAt)
        #expect(note.attachments.count == 1)
        #expect(exists(fixture, attachment))
    }

    // MARK: Reading

    /// Opening a preview is a read. It reaches the file system and nothing
    /// else.
    @Test
    func openingAnAttachmentChangesNothingAboutTheNote() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        let url = try #require(fixture.store.url(forStoredFilename: attachment.storedFilename))

        _ = try Data(contentsOf: url)

        #expect(note.updatedAt == savedAt)
        #expect(note.revisions.isEmpty)
        #expect(note.attachments.count == 1)
    }

    /// One file going missing costs that file and nothing else. The note still
    /// reads, still lists the attachment, and can still be deleted.
    @Test
    func aMissingFileLeavesTheNoteUsable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [
                DraftAttachment(staged: try fixture.stage("gone.pdf")),
                DraftAttachment(staged: try fixture.stage("kept.pdf")),
            ],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachments = NoteAttachments.attachments(of: note)
        let missing = try #require(attachments.first { $0.originalFilename == "gone.pdf" })
        let kept = try #require(attachments.first { $0.originalFilename == "kept.pdf" })
        let missingURL = try #require(fixture.store.url(forStoredFilename: missing.storedFilename))

        try FileManager.default.removeItem(at: missingURL)

        #expect(note.title == "Site Visit")
        #expect(note.body == "Walked the north wing.")
        #expect(NoteAttachments.attachments(of: note).count == 2)
        #expect(missing.descriptor.typeName == "PDF")
        #expect(!exists(fixture, missing))
        #expect(exists(fixture, kept))

        NoteAttachments.delete(note, in: fixture.context, using: fixture.store)
        try fixture.context.save()

        #expect(try fixture.context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(!exists(fixture, kept))
    }

    /// A stored name that has been corrupted cannot address a file, and the
    /// note has to survive that too.
    @Test
    func anUnusableStoredNameIsTreatedAsAMissingFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let attachment = try #require(NoteAttachments.attachments(of: note).first)
        attachment.storedFilename = "../escape.pdf"

        #expect(fixture.store.url(forStoredFilename: attachment.storedFilename) == nil)
        #expect(!exists(fixture, attachment))
        #expect(NoteAttachments.attachments(of: note).count == 1)

        NoteAttachments.delete(note, in: fixture.context, using: fixture.store)
        try fixture.context.save()

        #expect(try fixture.context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    // MARK: Drafts

    @Test
    func aDraftOpensWithTheNotesCurrentAttachments() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let draft = NoteDraft(note: note)

        #expect(draft.attachments.count == 1)
        #expect(draft.attachments.first?.descriptor.originalFilename == "site-plan.pdf")
        #expect(draft.attachments.first?.storedAttachment != nil)
        #expect(draft.attachments.first?.stagedFile == nil)
    }

    /// The editor decides it has unsaved work by comparing drafts, so an
    /// attachment change has to make them differ.
    @Test
    func stagingOrRemovingAFileMakesADraftDifferFromTheOneItOpenedWith() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        let original = NoteDraft(note: note)

        var added = original
        added.attachments.append(DraftAttachment(staged: try fixture.stage("mitigation.docx")))
        #expect(added != original)

        var removed = original
        removed.attachments.removeAll()
        #expect(removed != original)
        #expect(original == NoteDraft(note: note))
    }

    /// Applying a draft writes what the model itself holds. Files are
    /// reconciled separately, so a list change alone must not look like a field
    /// change.
    @Test
    func applyingADraftDoesNotTouchAttachments() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let note = makeNote(in: fixture, at: savedAt)
        NoteAttachments.apply(
            [DraftAttachment(staged: try fixture.stage("site-plan.pdf"))],
            to: note,
            in: fixture.context,
            using: fixture.store,
            at: savedAt
        )

        var draft = NoteDraft(note: note)
        draft.attachments.removeAll()

        #expect(!draft.hasChanges(comparedTo: note))
        #expect(!draft.apply(to: note, at: editedAt))
        #expect(note.attachments.count == 1)
        #expect(note.updatedAt == savedAt)
    }
}
