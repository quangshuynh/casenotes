//
//  NoteAttachments.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation
import SwiftData

/// The rules behind a note's attached files: what order they read in, what a
/// save does to them, and what has to happen before a note is deleted.
///
/// Every write that can add or remove an attachment goes through here, so there
/// is one answer to "what did that save do to the files" rather than one answer
/// per screen. The division of labour is deliberate: ``AttachmentStore`` owns
/// the file system and knows nothing about notes, this type owns the model
/// rules and reaches the file system only through the store.
///
/// Two rules matter more than the rest:
///
/// - Attaching or removing a file is a substantive change to a note, so a save
///   that changes the attachment list moves ``Note/updatedAt``.
/// - It is not a change to the note's writing, so it never records a
///   ``NoteRevision``. Version history stays text only, which is why this runs
///   beside ``NoteHistory`` rather than inside it.
enum NoteAttachments {
    /// A note's attachments, oldest first.
    ///
    /// SwiftData guarantees nothing about the order of a relationship array, so
    /// the order is established here instead, the same way history is. Ties are
    /// broken down to identity so two files attached in the same instant always
    /// list in the same order rather than shuffling between updates.
    ///
    /// - Parameter note: The note whose attachments are being read.
    /// - Returns: The attachments in display order.
    static func attachments(of note: Note) -> [NoteAttachment] {
        note.attachments.sorted { isOrderedBefore($0, $1) }
    }

    /// The editor's starting list for a note.
    ///
    /// - Parameter note: The note being edited.
    /// - Returns: One draft item per saved attachment, in display order.
    static func draftAttachments(of note: Note) -> [DraftAttachment] {
        attachments(of: note).map { DraftAttachment(attachment: $0) }
    }

    /// Applies an edited attachment list to a note.
    ///
    /// Additions are committed before removals are carried out, so a file
    /// system that refuses a write cannot leave the note having lost an
    /// attachment it was only meant to keep. Each commit is a move inside the
    /// app container, which is why a save applies as one step per file rather
    /// than as a copy that could stop halfway.
    ///
    /// A staged file that cannot be committed is dropped rather than left
    /// half-attached: the record is not written, so the note never refers to
    /// bytes that are not there.
    ///
    /// - Parameters:
    ///   - items: The list the editor finished with.
    ///   - note: The persistent note to update in place.
    ///   - context: The context that owns the note, used to insert and delete
    ///     attachment records.
    ///   - store: The store that owns the files.
    ///   - date: The timestamp recorded when the list changed. Injectable so
    ///     tests can assert on an exact value.
    /// - Returns: `true` when the note's attachments changed.
    @discardableResult
    static func apply(
        _ items: [DraftAttachment],
        to note: Note,
        in context: ModelContext,
        using store: AttachmentStore = .shared,
        at date: Date = Date()
    ) -> Bool {
        var changed = false

        // Read before anything is inserted. The removal pass below asks which
        // of the note's attachments the draft still lists, and a record added a
        // moment ago is not in that list: it came from a staged file, not from
        // one the draft was opened with, so walking the live relationship
        // afterwards would delete every file this save had just added.
        let existing = note.attachments

        for item in items {
            guard let staged = item.stagedFile else {
                continue
            }

            guard let storedFilename = try? store.commit(staged) else {
                store.discard(staged)
                continue
            }

            let attachment = NoteAttachment(
                id: staged.id,
                originalFilename: staged.descriptor.originalFilename,
                storedFilename: storedFilename,
                contentTypeIdentifier: staged.descriptor.contentTypeIdentifier,
                byteCount: staged.descriptor.byteCount,
                createdAt: date
            )

            context.insert(attachment)
            attachment.note = note
            changed = true
        }

        let kept = Set(items.compactMap { $0.storedAttachment?.persistentModelID })
        var removedFilenames: [String] = []

        for attachment in existing where !kept.contains(attachment.persistentModelID) {
            removedFilenames.append(attachment.storedFilename)
            attachment.note = nil
            context.delete(attachment)
            changed = true
        }

        if changed {
            note.updatedAt = date
        }

        // The store is written before the bytes are thrown away, because the
        // two cannot be made one transaction and the order decides how a
        // failure looks. Records first means an interruption leaves a file
        // nothing points at, which is invisible. Files first means it leaves a
        // record pointing at nothing, which the reader has to be shown as a
        // missing attachment. This was not theoretical: killing the app
        // immediately after a save produced exactly that row.
        removeFiles(named: removedFilenames, in: context, using: store)

        return changed
    }

    /// Deletes a note along with the files its attachments own.
    ///
    /// The cascade on ``Note/attachments`` removes the records, and records are
    /// all it can remove: SwiftData knows nothing about the app's attachments
    /// directory, so bytes deleted by a cascade alone would be left behind
    /// forever. Note deletion therefore goes through here rather than calling
    /// the context directly.
    ///
    /// - Parameters:
    ///   - note: The note to delete.
    ///   - context: The context that owns it.
    ///   - store: The store that owns the files.
    static func delete(
        _ note: Note,
        in context: ModelContext,
        using store: AttachmentStore = .shared
    ) {
        let filenames = note.attachments.map(\.storedFilename)

        context.delete(note)
        removeFiles(named: filenames, in: context, using: store)
    }

    /// Throws away the files an abandoned edit staged.
    ///
    /// Cancel has to undo the import as well as the list, or a discarded edit
    /// would leave its documents sitting in staging. Saved attachments in the
    /// list are untouched, including any the edit had marked for removal.
    ///
    /// - Parameters:
    ///   - items: The list the editor was holding.
    ///   - store: The store that owns the files.
    static func discardStaged(
        _ items: [DraftAttachment],
        using store: AttachmentStore = .shared
    ) {
        for staged in items.compactMap(\.stagedFile) {
            store.discard(staged)
        }
    }

    /// Writes the pending model changes, then deletes the files they gave up.
    ///
    /// Saving here rather than leaving it to the context's own timing is the
    /// point: a file must never be deleted while the record naming it is still
    /// only in memory, or an interruption before the next automatic save turns
    /// a removed attachment into one the note still lists and cannot open. A
    /// save that fails simply leaves the files alone, which is the same safe
    /// direction.
    ///
    /// - Parameters:
    ///   - filenames: The stored names whose bytes are no longer referenced.
    ///   - context: The context holding the removals.
    ///   - store: The store that owns the files.
    private static func removeFiles(
        named filenames: [String],
        in context: ModelContext,
        using store: AttachmentStore
    ) {
        guard !filenames.isEmpty else {
            return
        }

        do {
            try context.save()
        } catch {
            return
        }

        for filename in filenames {
            store.removeStoredFile(named: filename)
        }
    }

    /// Orders two attachments oldest first.
    ///
    /// - Parameters:
    ///   - lhs: An attachment.
    ///   - rhs: The attachment to compare it against.
    /// - Returns: `true` when `lhs` belongs above `rhs`.
    private static func isOrderedBefore(
        _ lhs: NoteAttachment,
        _ rhs: NoteAttachment
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        if lhs.originalFilename != rhs.originalFilename {
            return lhs.originalFilename < rhs.originalFilename
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
