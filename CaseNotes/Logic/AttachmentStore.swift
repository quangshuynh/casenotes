//
//  AttachmentStore.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Word document in the Open XML format.
    ///
    /// The SDK exposes no constant for it, and the identifier is resolved
    /// rather than assumed so a system that does not declare the type leaves it
    /// out of the importer instead of falling back to something broader.
    static var wordDocument: UTType? {
        UTType("org.openxmlformats.wordprocessingml.document")
            ?? UTType(filenameExtension: "docx")
    }
}

/// Why a file could not be attached.
///
/// Every case is a condition the importer can actually meet: a document that
/// has gone away, one the app does not accept, one with nothing in it, or a
/// copy the file system refused. They are surfaced to the user rather than
/// swallowed, because an attachment that silently fails to arrive reads as a
/// lost file.
enum AttachmentError: LocalizedError, Equatable {
    /// The chosen file could not be read, or is not a regular file.
    case unreadableSource

    /// The file is of a kind CaseNotes does not accept.
    case unsupportedType(String)

    /// The file holds no bytes.
    case emptyFile

    /// The file could not be copied into the app's own storage.
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            "That file could not be read."
        case let .unsupportedType(name):
            "\(name) is not a kind of file CaseNotes can attach."
        case .emptyFile:
            "That file is empty."
        case .copyFailed:
            "That file could not be copied into CaseNotes."
        }
    }
}

/// A file copied into staging by an edit that has not been saved.
///
/// Staging is what makes Cancel real for attachments, exactly as ``NoteDraft``
/// does for text: the bytes are already inside the app container, so a save is
/// a move rather than a copy that could fail halfway, but nothing about the
/// note has changed yet and discarding costs one file deletion.
///
/// The URL is transient and is never persisted. What survives a save is the
/// stored file name, which is derived from ``id``.
struct StagedAttachment: Identifiable, Equatable, Hashable, Sendable {
    /// Identity of the eventual attachment, and the stem of its file name.
    let id: UUID

    /// What the file is, for the row that shows it.
    let descriptor: AttachmentDescriptor

    /// Where the copy currently sits inside the staging directory.
    let url: URL
}

/// The one place that owns attachment files on disk.
///
/// Attachment bytes are deliberately not stored in SwiftData. A note's text is
/// small and a document is not, so the store keeps metadata and the file system
/// keeps the file, which is the same division drawings already make with
/// external storage.
///
/// Two directories, with different lifetimes:
///
/// - `Attachments` holds files that belong to saved notes. Nothing is written
///   there until a save, and nothing is left there once the owning note or
///   attachment is deleted.
/// - A staging directory under the container's temporary area holds files an
///   edit has imported but not saved. Cancel empties what it staged, and the
///   whole directory is cleared at launch so an interrupted edit leaves nothing
///   behind.
///
/// Files are named after a UUID rather than after the document, so two files
/// called the same thing cannot collide and no file name the user chose has to
/// be made safe for a path. The name the user knows is kept as metadata.
///
/// Only the file name is persisted, never a URL. Sandbox paths move between
/// installs, so a stored absolute path would be stale the moment the container
/// changed; the URL is rebuilt from the directory and the name on every read.
struct AttachmentStore: Sendable {
    /// Files belonging to saved notes.
    let attachmentsDirectory: URL

    /// Files staged by an edit that has not been saved.
    let stagingDirectory: URL

    /// The kinds of file the importer offers and accepts.
    ///
    /// PDF and Word documents are the point of the feature. Plain text,
    /// Markdown, and the two common image formats are included because the same
    /// import path already handles them and Quick Look already previews them,
    /// not because the list is meant to grow toward accepting anything.
    static let supportedContentTypes: [UTType] = [
        .pdf, .plainText, .png, .jpeg, .wordDocument,
    ].compactMap { $0 }

    /// The store the application uses.
    ///
    /// Application Support rather than Documents: these files are the app's own
    /// copies of what the user attached, they are restored with the note they
    /// belong to, and they are not meant to be browsed independently.
    static let shared = AttachmentStore(containerDirectory: .applicationSupportDirectory)

    /// - Parameters:
    ///   - containerDirectory: Directory the `Attachments` directory is created
    ///     inside. Injectable so tests never touch the real container.
    ///   - stagingParentDirectory: Directory the staging directory is created
    ///     inside. Defaults to the container's temporary area, which the system
    ///     is free to purge.
    init(
        containerDirectory: URL,
        stagingParentDirectory: URL = .temporaryDirectory
    ) {
        attachmentsDirectory = containerDirectory
            .appending(path: "Attachments", directoryHint: .isDirectory)
        stagingDirectory = stagingParentDirectory
            .appending(path: "AttachmentStaging", directoryHint: .isDirectory)
    }

    /// Copies a chosen file into staging.
    ///
    /// The content type is read from the file rather than inferred from its
    /// name, so a document that was renamed is still recognized for what it is
    /// and a name with a misleading extension cannot get a file past the
    /// accepted list. Security-scoped access is taken for the duration, since a
    /// file chosen outside the sandbox is otherwise unreadable, and the read is
    /// coordinated so a document owned by a file provider is copied in a
    /// consistent state.
    ///
    /// - Parameter source: The file the user chose.
    /// - Returns: The staged copy, ready to be shown in the editor.
    /// - Throws: ``AttachmentError`` when the file cannot be read, is of a kind
    ///   the app does not accept, is empty, or cannot be copied.
    func stage(contentsOf source: URL) throws -> StagedAttachment {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        var outcome: Result<StagedAttachment, Error>?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(
            readingItemAt: source,
            options: .withoutChanges,
            error: &coordinationError
        ) { readable in
            outcome = Result { try copyIntoStaging(from: readable, named: source.lastPathComponent) }
        }

        if coordinationError != nil {
            throw AttachmentError.unreadableSource
        }

        guard let outcome else {
            throw AttachmentError.unreadableSource
        }

        return try outcome.get()
    }

    /// Moves a staged file into permanent storage.
    ///
    /// A move rather than a copy, because both directories live inside the app
    /// container: the bytes are already written and only the name changes, so a
    /// save cannot half-write a document. A move that the file system refuses
    /// is retried as a copy before the attachment is given up on.
    ///
    /// - Parameter staged: The staged file to keep.
    /// - Returns: The file name to persist on the attachment record.
    /// - Throws: ``AttachmentError/copyFailed`` when the file could not be
    ///   placed in the attachments directory.
    func commit(_ staged: StagedAttachment) throws -> String {
        let storedFilename = staged.url.lastPathComponent
        let destination = attachmentsDirectory.appending(path: storedFilename)

        try? FileManager.default.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.moveItem(at: staged.url, to: destination)
            return storedFilename
        } catch {
            guard (try? FileManager.default.copyItem(at: staged.url, to: destination)) != nil else {
                throw AttachmentError.copyFailed
            }

            try? FileManager.default.removeItem(at: staged.url)
            return storedFilename
        }
    }

    /// Where a stored file sits now.
    ///
    /// Rebuilt from the directory and the name on every call. A name that is
    /// not a single path component is refused rather than resolved, so a stored
    /// value that has been tampered with or corrupted cannot address anything
    /// outside the attachments directory.
    ///
    /// - Parameter storedFilename: The name persisted on the attachment.
    /// - Returns: The file's URL, or `nil` when the name is not usable.
    func url(forStoredFilename storedFilename: String) -> URL? {
        guard isAddressable(storedFilename) else {
            return nil
        }

        return attachmentsDirectory.appending(path: storedFilename)
    }

    /// Whether the bytes behind a stored name are still there.
    ///
    /// - Parameter storedFilename: The name persisted on the attachment.
    /// - Returns: `true` when a readable file exists.
    func storedFileExists(named storedFilename: String) -> Bool {
        guard let url = url(forStoredFilename: storedFilename) else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Deletes a stored file.
    ///
    /// Best effort on purpose. This is called while a note or an attachment is
    /// being removed, and a file that has already gone, or one the system will
    /// not let go of, must not stop the record from being deleted.
    ///
    /// - Parameter storedFilename: The name persisted on the attachment.
    func removeStoredFile(named storedFilename: String) {
        guard let url = url(forStoredFilename: storedFilename) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes a staged file that is not going to be saved.
    ///
    /// - Parameter staged: The staged file to discard.
    func discard(_ staged: StagedAttachment) {
        try? FileManager.default.removeItem(at: staged.url)
    }

    /// Empties the staging directory.
    ///
    /// Called once at launch. An edit that was interrupted by a crash or by the
    /// system ending the app has no owner left to cancel it, so its staged files
    /// are cleared rather than left to accumulate.
    func purgeStaging() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    /// Copies a readable file into the staging directory.
    ///
    /// - Parameters:
    ///   - source: The coordinated URL to read from.
    ///   - originalFilename: The name the user knows the file by, which may
    ///     differ from the coordinated URL's own last component.
    /// - Returns: The staged copy.
    /// - Throws: ``AttachmentError``.
    private func copyIntoStaging(
        from source: URL,
        named originalFilename: String
    ) throws -> StagedAttachment {
        let values = try? source.resourceValues(
            forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey]
        )

        guard values?.isRegularFile == true else {
            throw AttachmentError.unreadableSource
        }

        let contentType = values?.contentType
            ?? UTType(filenameExtension: source.pathExtension)
            ?? .data

        guard Self.supportedContentTypes.contains(where: contentType.conforms(to:)) else {
            throw AttachmentError.unsupportedType(originalFilename)
        }

        let byteCount = Int64(values?.fileSize ?? 0)

        guard byteCount > 0 else {
            throw AttachmentError.emptyFile
        }

        let id = UUID()
        let destination = stagingDirectory.appending(
            path: storedFilename(for: id, contentType: contentType, originalFilename: originalFilename)
        )

        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw AttachmentError.copyFailed
        }

        return StagedAttachment(
            id: id,
            descriptor: AttachmentDescriptor(
                originalFilename: originalFilename,
                contentTypeIdentifier: contentType.identifier,
                byteCount: byteCount
            ),
            url: destination
        )
    }

    /// The name a file is stored under.
    ///
    /// The stem is the attachment's identity, which is what makes two documents
    /// with the same name safe to keep side by side. The extension comes from
    /// the resolved content type so the file describes itself to Quick Look,
    /// and falls back to the original name's extension only when the type has
    /// no preferred one.
    ///
    /// - Parameters:
    ///   - id: The attachment's identity.
    ///   - contentType: The resolved type of the file.
    ///   - originalFilename: The name the user knows the file by.
    /// - Returns: A single path component.
    private func storedFilename(
        for id: UUID,
        contentType: UTType,
        originalFilename: String
    ) -> String {
        let candidate = contentType.preferredFilenameExtension
            ?? (originalFilename as NSString).pathExtension

        let allowed = CharacterSet.alphanumerics
        let cleaned = candidate.unicodeScalars.filter(allowed.contains)

        guard !cleaned.isEmpty else {
            return id.uuidString
        }

        return "\(id.uuidString).\(String(String.UnicodeScalarView(cleaned)))"
    }

    /// Whether a persisted name addresses a file inside the attachments
    /// directory and nowhere else.
    ///
    /// - Parameter storedFilename: The name persisted on the attachment.
    /// - Returns: `true` when the name is a single, ordinary path component.
    private func isAddressable(_ storedFilename: String) -> Bool {
        !storedFilename.isEmpty
            && storedFilename != "."
            && storedFilename != ".."
            && !storedFilename.contains("/")
            && !storedFilename.contains("\0")
    }
}
