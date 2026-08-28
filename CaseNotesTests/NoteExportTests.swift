//
//  NoteExportTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import Testing
@testable import CaseNotes

@MainActor
struct NoteExportTests {
    /// Fixed locale and time zone so exported dates are asserted on exactly,
    /// rather than following whichever region the test machine is set to.
    private let locale = Locale(identifier: "en_US_POSIX")
    private let timeZone = TimeZone(identifier: "GMT")!
    private let eventDate = Date(timeIntervalSince1970: 1_700_086_400)

    private func markdown(
        for note: Note,
        includingAttribution: Bool = true
    ) -> String {
        NoteExport.markdown(
            for: note,
            includingAttribution: includingAttribution,
            locale: locale,
            timeZone: timeZone
        )
    }

    @Test
    func exportLeadsWithTheTitleAsAHeading() {
        let note = Note(title: "Site Visit", body: "Walked the north wing.")

        #expect(
            markdown(for: note, includingAttribution: false) == """
            # Site Visit

            Walked the north wing.
            """
        )
    }

    @Test
    func exportIncludesTheEventDateWhenPresent() {
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            eventDate: eventDate
        )

        #expect(
            markdown(for: note, includingAttribution: false) == """
            # Site Visit

            *Event date: November 15, 2023*

            Walked the north wing.
            """
        )
    }

    @Test
    func exportOmitsTheEventDateLineWhenAbsent() {
        let note = Note(title: "Site Visit", body: "Walked the north wing.")

        #expect(!markdown(for: note).contains("Event date"))
    }

    @Test
    func attributionIsAppendedAfterARule() {
        let note = Note(title: "Site Visit", body: "Walked the north wing.")

        #expect(
            markdown(for: note) == """
            # Site Visit

            Walked the north wing.

            ---

            Created with CaseNotes
            """
        )
    }

    @Test
    func copyingANoteCarriesNoAttribution() {
        let note = Note(title: "Site Visit", body: "Walked the north wing.")

        #expect(!markdown(for: note, includingAttribution: false).contains("CaseNotes"))
    }

    @Test
    func markdownBodyFormattingIsPassedThroughUntouched() {
        let body = """
        ## Actions

        - Photograph the stairwell
        - Check the **handrail**

        > Parts are on order.
        """
        let note = Note(title: "Site Visit", body: body)

        #expect(markdown(for: note, includingAttribution: false).contains(body))
    }

    @Test
    func exportOmitsPrivateAppMetadata() {
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            isPinned: true
        )

        let export = markdown(for: note)

        #expect(!export.localizedCaseInsensitiveContains("pinned"))
        #expect(!export.localizedCaseInsensitiveContains("created at"))
        #expect(!export.localizedCaseInsensitiveContains("updated"))
        #expect(!export.contains("2023-11-14"))
    }

    @Test
    func emptyBodyStillExportsATitle() {
        let note = Note(title: "Site Visit", body: "   \n  ")

        #expect(
            markdown(for: note, includingAttribution: false) == "# Site Visit"
        )
    }

    @Test
    func untitledNotesExportWithAPlaceholderTitle() {
        let note = Note(title: "  ", body: "Walked the north wing.")

        #expect(markdown(for: note, includingAttribution: false).hasPrefix("# Untitled Note"))
        #expect(NoteExport.fileBaseName(for: note) == "Untitled Note")
    }

    @Test
    func fileNameUsesTheTitleWithAMarkdownExtension() {
        let note = Note(title: "Site Visit")

        #expect(NoteExport.suggestedFileName(for: note) == "Site Visit.md")
    }

    @Test
    func fileNameStripsPathUnsafeCharacters() {
        let note = Note(title: "Budget: Q3/Q4 <draft>")

        #expect(NoteExport.fileBaseName(for: note) == "Budget Q3 Q4 draft")
    }

    @Test
    func fileNameCollapsesWhitespaceAndNewlines() {
        let note = Note(title: "Site   Visit\nNorth")

        #expect(NoteExport.fileBaseName(for: note) == "Site Visit North")
    }

    @Test
    func fileNameIsCappedInLength() {
        let note = Note(title: String(repeating: "a", count: 200))

        #expect(NoteExport.fileBaseName(for: note).count == 60)
    }

    @Test
    func markdownFilePackagesTheSameDocumentAsTheShareText() {
        let note = Note(
            title: "Site Visit",
            body: "Walked the north wing.",
            eventDate: eventDate
        )

        let file = MarkdownNoteFile(note: note, locale: locale, timeZone: timeZone)

        #expect(file.fileName == "Site Visit.md")
        #expect(file.markdown == markdown(for: note))
    }
}
