//
//  InlineAttachmentSource.swift
//  CaseNotes
//
//  Created by q on 9/3/26.
//

import Foundation
import UniformTypeIdentifiers

/// One inline placement resolved against the files a note actually holds.
///
/// The body says which attachment a placement refers to and nothing more, so
/// everything a row or an image needs is gathered here: what the file is
/// called, what kind of file it is, and where its bytes are. A placement whose
/// bytes have gone still resolves, with no URL, because the reader is better
/// served by a row that says the file is missing than by a gap.
struct ResolvedInlineAttachment: Identifiable, Equatable {
    let id: UUID

    let descriptor: AttachmentDescriptor

    /// Where the file is now, or `nil` when the bytes are no longer there.
    let url: URL?

    /// Whether the file is one the app can draw in the note itself.
    ///
    /// Images are shown; everything else is named. A PDF or a Word document is
    /// opened in Quick Look, which already reads both, rather than rendered by
    /// anything of ours.
    var isImage: Bool {
        descriptor.contentType?.conforms(to: .image) == true
    }
}

/// Answers what an inline placement refers to.
///
/// Resolution is settled once, when the source is built, rather than per row.
/// Whether a file exists is a file system call, and a note being typed into
/// redraws on every keystroke, so asking on each redraw would put the disk on
/// the typing path. A view therefore rebuilds this when the note's list of
/// files changes and not otherwise.
///
/// An unknown identity is not an error. Markdown outlives the files it names,
/// so a body may refer to an attachment that has since been deleted, and the
/// honest answer is `nil` and a row that says so, with the author's source left
/// exactly as they wrote it.
struct InlineAttachmentSource {
    private let resolved: [UUID: ResolvedInlineAttachment]

    /// A source that resolves nothing, for surfaces that show Markdown without
    /// a note behind it.
    static let unavailable = InlineAttachmentSource(resolved: [:])

    private init(resolved: [UUID: ResolvedInlineAttachment]) {
        self.resolved = resolved
    }

    /// Resolves the files a saved note holds.
    ///
    /// - Parameters:
    ///   - attachments: The note's attachment records.
    ///   - store: The store that owns the files.
    init(attachments: [NoteAttachment], store: AttachmentStore = .shared) {
        self.init(
            resolved: Self.index(
                attachments.map { attachment in
                    ResolvedInlineAttachment(
                        id: attachment.id,
                        descriptor: attachment.descriptor,
                        url: Self.readableURL(
                            named: attachment.storedFilename,
                            in: store
                        )
                    )
                }
            )
        )
    }

    /// Resolves the files an edit in progress is holding.
    ///
    /// A staged file is resolved to its copy in staging, so a document placed
    /// in the body during an edit renders straight away rather than waiting for
    /// a save. Its identity is already the identity the saved attachment will
    /// have, which is why a marker written now survives the save unchanged.
    ///
    /// - Parameters:
    ///   - draftAttachments: The editor's list of files.
    ///   - store: The store that owns the files.
    init(draftAttachments: [DraftAttachment], store: AttachmentStore = .shared) {
        self.init(
            resolved: Self.index(
                draftAttachments.map { item in
                    ResolvedInlineAttachment(
                        id: item.id,
                        descriptor: item.descriptor,
                        url: Self.readableURL(for: item, in: store)
                    )
                }
            )
        )
    }

    /// The attachment a placement names.
    ///
    /// - Parameter id: The identity a marker carries.
    /// - Returns: The resolved attachment, or `nil` when the note no longer
    ///   holds it.
    func attachment(for id: UUID) -> ResolvedInlineAttachment? {
        resolved[id]
    }

    /// Where a draft item's bytes are.
    ///
    /// - Parameters:
    ///   - item: A file the editor is holding.
    ///   - store: The store that owns the files.
    /// - Returns: The file's URL, or `nil` when it cannot be read.
    private static func readableURL(
        for item: DraftAttachment,
        in store: AttachmentStore
    ) -> URL? {
        if let staged = item.stagedFile {
            let path = staged.url.path(percentEncoded: false)

            return FileManager.default.fileExists(atPath: path) ? staged.url : nil
        }

        guard let attachment = item.storedAttachment else {
            return nil
        }

        return readableURL(named: attachment.storedFilename, in: store)
    }

    /// Where a saved attachment's bytes are, if they are still there.
    ///
    /// - Parameters:
    ///   - storedFilename: The name persisted on the attachment.
    ///   - store: The store that owns the files.
    /// - Returns: The file's URL, or `nil` when the name is unusable or the
    ///   file has gone.
    private static func readableURL(
        named storedFilename: String,
        in store: AttachmentStore
    ) -> URL? {
        guard store.storedFileExists(named: storedFilename) else {
            return nil
        }

        return store.url(forStoredFilename: storedFilename)
    }

    /// Keys resolved attachments by identity, keeping the first of a repeat.
    ///
    /// - Parameter attachments: The resolved attachments in display order.
    /// - Returns: The lookup a placement is answered from.
    private static func index(
        _ attachments: [ResolvedInlineAttachment]
    ) -> [UUID: ResolvedInlineAttachment] {
        Dictionary(attachments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
