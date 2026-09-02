//
//  NoteAttachment.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation
import SwiftData

/// A file kept with a note, such as a PDF or a Word document.
///
/// The record is metadata only. The bytes live in the app's own attachments
/// directory under ``storedFilename``, which ``AttachmentStore`` owns, for the
/// same reason drawings use external storage: a document is orders of magnitude
/// larger than the writing around it and browsing a note list must not pay for
/// it.
///
/// Two names, deliberately. ``storedFilename`` is derived from ``id`` so two
/// documents that arrived with the same name cannot collide and no name the
/// user chose has to be made safe for a path. ``originalFilename`` is the name
/// the reader recognizes, and is display metadata rather than the identity of
/// the file.
///
/// Nothing here is a path. Sandbox locations change between installs, so a
/// stored absolute URL would be stale the moment the container moved; the URL
/// is rebuilt from the store's directory and the file name on every read.
@Model
final class NoteAttachment {
    /// Stable identity, and the stem of the file's name on disk.
    var id: UUID = UUID()

    /// The name the file arrived with, shown to the reader.
    var originalFilename: String

    /// The name of the file inside the attachments directory.
    var storedFilename: String

    /// The uniform type identifier resolved when the file was imported.
    ///
    /// Read from the file itself rather than inferred from its name, so a
    /// document that was renamed still describes itself correctly.
    var contentTypeIdentifier: String

    /// The size of the file when it was imported.
    ///
    /// Recorded rather than measured on demand so a list of attachments reads
    /// without touching the file system per row.
    var byteCount: Int64

    /// When the file was attached.
    var createdAt: Date

    /// The note this file belongs to.
    ///
    /// The owning side is ``Note/attachments``, which cascades, so a record
    /// never outlives its note. The cascade removes the record and not the
    /// bytes, which is why note deletion goes through
    /// ``NoteAttachments/delete(_:in:using:)``.
    var note: Note?

    init(
        id: UUID = UUID(),
        originalFilename: String = "",
        storedFilename: String = "",
        contentTypeIdentifier: String = "",
        byteCount: Int64 = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.createdAt = createdAt
    }

    /// What this file is, for the rows that show it.
    var descriptor: AttachmentDescriptor {
        AttachmentDescriptor(
            originalFilename: originalFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: byteCount
        )
    }
}

/// One attachment as the editor sees it, whether it is already saved with the
/// note or has only been staged by the edit in progress.
///
/// The editor works on a list of these for the same reason it works on a
/// ``NoteDraft``: nothing about the note may change until the user saves. A
/// staged item names a file sitting in staging, a stored item names a record
/// that is already persisted, and removing either from the list is a decision
/// that only takes effect on Save.
struct DraftAttachment: Identifiable, Equatable {
    /// Where the file behind a draft item currently lives.
    enum Origin: Equatable {
        /// A file already saved with the note.
        case stored(NoteAttachment)

        /// A file this edit copied into staging.
        case staged(StagedAttachment)
    }

    let id: UUID
    let descriptor: AttachmentDescriptor
    let origin: Origin

    /// Wraps an attachment the note already has.
    ///
    /// - Parameter attachment: The persisted record.
    init(attachment: NoteAttachment) {
        id = attachment.id
        descriptor = attachment.descriptor
        origin = .stored(attachment)
    }

    /// Wraps a file the current edit has staged.
    ///
    /// - Parameter staged: The staged copy.
    init(staged: StagedAttachment) {
        id = staged.id
        descriptor = staged.descriptor
        origin = .staged(staged)
    }

    /// The staged file behind this item, if it has one.
    var stagedFile: StagedAttachment? {
        guard case let .staged(staged) = origin else {
            return nil
        }

        return staged
    }

    /// The persisted record behind this item, if it has one.
    var storedAttachment: NoteAttachment? {
        guard case let .stored(attachment) = origin else {
            return nil
        }

        return attachment
    }
}
