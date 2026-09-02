//
//  AttachmentStoreTests.swift
//  CaseNotesTests
//
//  Created by q on 9/2/26.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CaseNotes

/// Behavior of the type that owns attachment files.
///
/// Every case runs against a store rooted in its own temporary directory, so
/// nothing here reads or writes the real application container.
@MainActor
struct AttachmentStoreTests {
    /// A store and the directory it owns, removed when the test finishes.
    private struct Fixture {
        let root: URL
        let store: AttachmentStore

        init() {
            root = URL.temporaryDirectory
                .appending(path: "casenotes-attachments-\(UUID().uuidString)")
            store = AttachmentStore(
                containerDirectory: root.appending(path: "container"),
                stagingParentDirectory: root.appending(path: "staging")
            )
        }

        /// Writes a source file for the importer to read.
        ///
        /// - Parameters:
        ///   - name: The file name, whose extension decides the resolved type.
        ///   - bytes: How many bytes to write.
        /// - Returns: The written file.
        func sourceFile(named name: String, bytes: Int = 64) throws -> URL {
            let directory = root.appending(path: "sources")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let url = directory.appending(path: name)
            try Data(repeating: 0x41, count: bytes).write(to: url)

            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: Staging

    @Test
    func stagesAPDFWithItsNameTypeAndSize() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf", bytes: 128)
        let staged = try fixture.store.stage(contentsOf: source)

        #expect(staged.descriptor.originalFilename == "site-plan.pdf")
        #expect(staged.descriptor.contentTypeIdentifier == UTType.pdf.identifier)
        #expect(staged.descriptor.byteCount == 128)
        #expect(exists(staged.url))
    }

    @Test
    func stagesAWordDocument() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "mitigation.docx")
        let staged = try fixture.store.stage(contentsOf: source)

        #expect(staged.descriptor.typeName == "DOCX")
        #expect(exists(staged.url))
    }

    /// The copy lands inside staging and nowhere near the attachments the app
    /// has actually saved, which is what makes Cancel a deletion of one
    /// directory's worth of files.
    @Test
    func stagesIntoStagingRatherThanIntoSavedStorage() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let staged = try fixture.store.stage(contentsOf: source)

        #expect(staged.url.deletingLastPathComponent() == fixture.store.stagingDirectory)
        #expect(!exists(fixture.store.attachmentsDirectory.appending(path: staged.url.lastPathComponent)))
    }

    /// The name on disk is the attachment's identity, so two documents that
    /// arrived under the same name cannot overwrite one another.
    @Test
    func givesTwoFilesOfTheSameNameDifferentStoredNames() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let first = try fixture.store.stage(contentsOf: source)
        let second = try fixture.store.stage(contentsOf: source)

        #expect(first.descriptor.originalFilename == second.descriptor.originalFilename)
        #expect(first.url.lastPathComponent != second.url.lastPathComponent)
        #expect(exists(first.url))
        #expect(exists(second.url))
    }

    @Test
    func refusesAFileOfAKindTheAppDoesNotAccept() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "bundle.zip")

        #expect(throws: AttachmentError.unsupportedType("bundle.zip")) {
            try fixture.store.stage(contentsOf: source)
        }
    }

    @Test
    func refusesAnEmptyFile() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "blank.pdf", bytes: 0)

        #expect(throws: AttachmentError.emptyFile) {
            try fixture.store.stage(contentsOf: source)
        }
    }

    @Test
    func refusesASourceThatIsNotThere() {
        let fixture = Fixture()
        defer { fixture.remove() }

        let missing = fixture.root.appending(path: "sources/gone.pdf")

        #expect(throws: AttachmentError.unreadableSource) {
            try fixture.store.stage(contentsOf: missing)
        }
    }

    @Test
    func refusesADirectory() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let directory = fixture.root.appending(path: "folder.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        #expect(throws: AttachmentError.unreadableSource) {
            try fixture.store.stage(contentsOf: directory)
        }
    }

    /// A file staged and then thrown away leaves nothing behind, which is what
    /// Cancel relies on.
    @Test
    func discardsAStagedFile() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let staged = try fixture.store.stage(contentsOf: source)

        fixture.store.discard(staged)

        #expect(!exists(staged.url))
        #expect(exists(source))
    }

    @Test
    func emptiesStagingOnRequest() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let staged = try fixture.store.stage(contentsOf: source)

        fixture.store.purgeStaging()

        #expect(!exists(staged.url))
        #expect(!exists(fixture.store.stagingDirectory))
    }

    // MARK: Committing

    @Test
    func commitMovesAStagedFileIntoSavedStorage() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let staged = try fixture.store.stage(contentsOf: source)
        let storedFilename = try fixture.store.commit(staged)
        let stored = try #require(fixture.store.url(forStoredFilename: storedFilename))

        #expect(exists(stored))
        #expect(!exists(staged.url))
        #expect(fixture.store.storedFileExists(named: storedFilename))
    }

    /// The stored name keeps the extension the resolved type prefers, so Quick
    /// Look is handed a file that describes itself.
    @Test
    func commitKeepsAnExtensionMatchingTheContentType() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "mitigation.docx")
        let staged = try fixture.store.stage(contentsOf: source)
        let storedFilename = try fixture.store.commit(staged)

        #expect(storedFilename.hasPrefix(staged.id.uuidString))
        #expect(storedFilename.hasSuffix(".docx"))
    }

    @Test
    func commitOfTwoFilesNamedAlikeProducesTwoFiles() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let first = try fixture.store.commit(try fixture.store.stage(contentsOf: source))
        let second = try fixture.store.commit(try fixture.store.stage(contentsOf: source))

        #expect(first != second)
        #expect(fixture.store.storedFileExists(named: first))
        #expect(fixture.store.storedFileExists(named: second))
    }

    // MARK: Reading and removing

    @Test
    func rebuildsAStoredURLFromTheDirectoryAndTheName() {
        let fixture = Fixture()
        defer { fixture.remove() }

        let url = fixture.store.url(forStoredFilename: "example.pdf")

        #expect(url == fixture.store.attachmentsDirectory.appending(path: "example.pdf"))
    }

    /// A stored name is metadata, and metadata can be wrong. A name that is not
    /// a single path component must not address anything at all.
    @Test(arguments: ["", ".", "..", "../escape.pdf", "nested/file.pdf"])
    func refusesAStoredNameThatIsNotASinglePathComponent(name: String) {
        let fixture = Fixture()
        defer { fixture.remove() }

        #expect(fixture.store.url(forStoredFilename: name) == nil)
        #expect(!fixture.store.storedFileExists(named: name))
    }

    @Test
    func reportsAStoredFileThatIsNoLongerThere() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let storedFilename = try fixture.store.commit(try fixture.store.stage(contentsOf: source))
        let stored = try #require(fixture.store.url(forStoredFilename: storedFilename))

        try FileManager.default.removeItem(at: stored)

        #expect(!fixture.store.storedFileExists(named: storedFilename))
    }

    @Test
    func removesAStoredFile() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let source = try fixture.sourceFile(named: "site-plan.pdf")
        let storedFilename = try fixture.store.commit(try fixture.store.stage(contentsOf: source))

        fixture.store.removeStoredFile(named: storedFilename)

        #expect(!fixture.store.storedFileExists(named: storedFilename))
    }

    /// Removal is called while a record is being deleted, so a file that has
    /// already gone must not turn into an error.
    @Test
    func removingAFileThatIsAlreadyGoneIsHarmless() {
        let fixture = Fixture()
        defer { fixture.remove() }

        fixture.store.removeStoredFile(named: "\(UUID().uuidString).pdf")
        fixture.store.removeStoredFile(named: "../escape.pdf")
    }

    // MARK: Accepted types

    @Test
    func offersTheFormatsTheFeatureIsFor() {
        #expect(AttachmentStore.supportedContentTypes.contains(.pdf))
        #expect(AttachmentStore.supportedContentTypes.contains(.plainText))
        #expect(AttachmentStore.supportedContentTypes.contains(.png))
        #expect(AttachmentStore.supportedContentTypes.contains(.jpeg))
        #expect(UTType.wordDocument != nil)
    }
}
