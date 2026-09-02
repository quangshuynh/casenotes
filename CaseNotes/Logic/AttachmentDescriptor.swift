//
//  AttachmentDescriptor.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation
import UniformTypeIdentifiers

/// What one attached file is: the name it arrived with, what kind of file it
/// is, and how big it is.
///
/// The same three facts describe a file that is already saved with a note and a
/// file the current edit has only staged, so both surfaces read from this rather
/// than each deriving its own wording. Keeping the derivations here also keeps
/// them testable: none of them needs a model, a context, or a view.
///
/// The content type identifier is the authority on what a file is. It is
/// resolved from the file itself when it is imported, so a document that was
/// renamed still describes itself correctly, and the original file name is
/// carried alongside as the label a reader recognizes rather than as the truth
/// about the format.
struct AttachmentDescriptor: Equatable, Hashable, Sendable {
    /// The file name as the user chose it, kept for display only.
    var originalFilename: String

    /// The uniform type identifier resolved when the file was imported.
    var contentTypeIdentifier: String

    /// The size of the file in bytes.
    var byteCount: Int64

    /// - Parameters:
    ///   - originalFilename: The file name to show.
    ///   - contentTypeIdentifier: The uniform type identifier of the file.
    ///   - byteCount: The size of the file in bytes.
    init(originalFilename: String, contentTypeIdentifier: String, byteCount: Int64) {
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
    }

    /// The resolved type, or `nil` when the stored identifier is not one this
    /// system knows.
    var contentType: UTType? {
        UTType(contentTypeIdentifier)
    }

    /// The short word naming the format, such as `PDF` or `DOCX`.
    ///
    /// Taken from the content type rather than from the file name, so a file
    /// that was renamed is still described by what it actually is. A type this
    /// system does not know falls back to the name's extension, and a file with
    /// neither is simply called a file rather than labelled with a guess.
    var typeName: String {
        if let preferred = contentType?.preferredFilenameExtension {
            return preferred.uppercased()
        }

        let extensionFromName = (originalFilename as NSString).pathExtension
        return extensionFromName.isEmpty ? "File" : extensionFromName.uppercased()
    }

    /// The SF Symbol standing in for this kind of file.
    ///
    /// Deliberately coarse. The symbol is a hint beside a name and a type that
    /// already say what the file is, so it groups formats rather than trying to
    /// give each one its own mark.
    var symbolName: String {
        guard let contentType else {
            return "doc"
        }

        if contentType.conforms(to: .pdf) {
            return "doc.richtext"
        }

        if contentType.conforms(to: .image) {
            return "photo"
        }

        if contentType.conforms(to: .plainText) {
            return "doc.plaintext"
        }

        return "doc.text"
    }

    /// The file size written for a reader.
    ///
    /// - Parameter locale: Locale used to format the number and its unit.
    ///   Injectable so tests do not depend on the machine's region.
    /// - Returns: A formatted size such as `42 KB`.
    func sizeText(locale: Locale = .autoupdatingCurrent) -> String {
        byteCount.formatted(.byteCount(style: .file).locale(locale))
    }

    /// The second line of a row: what kind of file it is and how big.
    ///
    /// - Parameter locale: Locale used to format the size.
    /// - Returns: The type and size joined by a separator.
    func detailText(locale: Locale = .autoupdatingCurrent) -> String {
        "\(typeName) \u{00B7} \(sizeText(locale: locale))"
    }

    /// The whole row spoken as one phrase.
    ///
    /// The separator between the type and the size is a symbol, so it is
    /// replaced with a comma rather than left for a screen reader to announce.
    ///
    /// - Parameter locale: Locale used to format the size.
    /// - Returns: The file name, its type, and its size.
    func spokenDescription(locale: Locale = .autoupdatingCurrent) -> String {
        "\(originalFilename), \(typeName), \(sizeText(locale: locale))"
    }
}
