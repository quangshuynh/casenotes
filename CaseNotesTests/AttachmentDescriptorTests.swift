//
//  AttachmentDescriptorTests.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CaseNotes

@MainActor
struct AttachmentDescriptorTests {
    private let locale = Locale(identifier: "en_US")

    private func descriptor(
        filename: String = "report.pdf",
        identifier: String = "com.adobe.pdf",
        byteCount: Int64 = 1_024
    ) -> AttachmentDescriptor {
        AttachmentDescriptor(
            originalFilename: filename,
            contentTypeIdentifier: identifier,
            byteCount: byteCount
        )
    }

    // MARK: Type naming

    @Test
    func namesAPDFByItsType() {
        #expect(descriptor().typeName == "PDF")
    }

    @Test
    func namesAWordDocumentByItsType() {
        let word = descriptor(
            filename: "mitigation.docx",
            identifier: "org.openxmlformats.wordprocessingml.document"
        )

        #expect(word.typeName == "DOCX")
    }

    /// The content type is the authority, not the name. A document that was
    /// renamed still has to describe itself correctly.
    @Test
    func prefersTheContentTypeOverTheFileNameExtension() {
        let renamed = descriptor(filename: "report.txt", identifier: "com.adobe.pdf")

        #expect(renamed.typeName == "PDF")
    }

    /// A store written on a system that knew a type, read on one that does not,
    /// still has the name to fall back on.
    @Test
    func fallsBackToTheNameExtensionForAnUnknownType() {
        let unknown = descriptor(
            filename: "notes.example",
            identifier: "com.example.unknown-type-identifier"
        )

        #expect(unknown.typeName == "EXAMPLE")
    }

    @Test
    func describesAFileWithNothingToGoOnAsAFile() {
        let unknown = descriptor(
            filename: "attachment",
            identifier: "com.example.unknown-type-identifier"
        )

        #expect(unknown.typeName == "File")
    }

    @Test
    func resolvesAKnownIdentifierAndLeavesAnUnknownOneNil() {
        #expect(descriptor().contentType == .pdf)
        #expect(descriptor(identifier: "com.example.nope").contentType == nil)
    }

    // MARK: Symbols

    @Test(arguments: [
        ("com.adobe.pdf", "doc.richtext"),
        ("public.png", "photo"),
        ("public.jpeg", "photo"),
        ("public.plain-text", "doc.plaintext"),
        ("org.openxmlformats.wordprocessingml.document", "doc.text"),
        ("com.example.unknown-type-identifier", "doc"),
    ])
    func groupsFormatsUnderOneSymbolEach(identifier: String, symbol: String) {
        #expect(descriptor(identifier: identifier).symbolName == symbol)
    }

    // MARK: Wording

    @Test
    func writesTheSizeForTheGivenLocale() {
        #expect(descriptor(byteCount: 43_008).sizeText(locale: locale) == "43 kB")
    }

    @Test
    func writesTheTypeAndSizeOnOneLine() {
        let text = descriptor(byteCount: 43_008).detailText(locale: locale)

        #expect(text == "PDF \u{00B7} 43 kB")
    }

    /// The separator is a symbol, so it is replaced rather than left for a
    /// screen reader to announce.
    @Test
    func speaksTheNameTheTypeAndTheSizeWithoutTheSeparator() {
        let spoken = descriptor(filename: "site-plan.pdf", byteCount: 43_008)
            .spokenDescription(locale: locale)

        #expect(spoken == "site-plan.pdf, PDF, 43 kB")
        #expect(!spoken.contains("\u{00B7}"))
    }
}
