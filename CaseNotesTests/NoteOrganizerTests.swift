//
//  NoteOrganizerTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

@MainActor
struct NoteOrganizerTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    @Test
    func allScopeIncludesFiledAndUnfiledNotes() throws {
        let context = try makeContext()
        let folder = Folder(name: "Inbox")
        context.insert(folder)

        let filed = Note(title: "Filed", folder: folder)
        let unfiled = Note(title: "Unfiled")
        context.insert(filed)
        context.insert(unfiled)

        let result = NoteOrganizer.organize(
            [filed, unfiled],
            scope: .all,
            searchText: "",
            sortOption: .updated
        )

        #expect(result.count == 2)
    }

    @Test
    func unfiledScopeExcludesFiledNotes() throws {
        let context = try makeContext()
        let folder = Folder(name: "Inbox")
        context.insert(folder)

        let filed = Note(title: "Filed", folder: folder)
        let unfiled = Note(title: "Unfiled")
        context.insert(filed)
        context.insert(unfiled)

        let result = NoteOrganizer.organize(
            [filed, unfiled],
            scope: .unfiled,
            searchText: "",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["Unfiled"])
    }

    @Test
    func folderScopeIncludesOnlyThatFolder() throws {
        let context = try makeContext()
        let inbox = Folder(name: "Inbox")
        let archive = Folder(name: "Archive")
        context.insert(inbox)
        context.insert(archive)

        let inInbox = Note(title: "In Inbox", folder: inbox)
        let inArchive = Note(title: "In Archive", folder: archive)
        let loose = Note(title: "Loose")
        context.insert(inInbox)
        context.insert(inArchive)
        context.insert(loose)

        let result = NoteOrganizer.organize(
            [inInbox, inArchive, loose],
            scope: .folder(inbox),
            searchText: "",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["In Inbox"])
    }

    @Test
    func searchMatchesTitleAndBodyCaseInsensitively() {
        let byTitle = Note(title: "Stairwell", body: "Nothing here")
        let byBody = Note(title: "Other", body: "Check the STAIRWELL lighting")
        let unrelated = Note(title: "Reading", body: "Papers")

        let result = NoteOrganizer.organize(
            [byTitle, byBody, unrelated],
            scope: .all,
            searchText: "stairwell",
            sortOption: .updated
        )

        #expect(result.count == 2)
        #expect(!result.contains { $0.title == "Reading" })
    }

    @Test
    func searchIsScopedToTheSelectedFolder() throws {
        let context = try makeContext()
        let inbox = Folder(name: "Inbox")
        context.insert(inbox)

        let inScope = Note(title: "Stairwell", folder: inbox)
        let outOfScope = Note(title: "Stairwell elsewhere")
        context.insert(inScope)
        context.insert(outOfScope)

        let result = NoteOrganizer.organize(
            [inScope, outOfScope],
            scope: .folder(inbox),
            searchText: "stairwell",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["Stairwell"])
    }

    @Test
    func whitespaceOnlySearchDoesNotFilter() {
        let notes = [Note(title: "One"), Note(title: "Two")]

        let result = NoteOrganizer.organize(
            notes,
            scope: .all,
            searchText: "   ",
            sortOption: .updated
        )

        #expect(result.count == 2)
    }

    @Test
    func pinnedNotesSortAheadOfUnpinnedOnes() {
        let pinnedOld = Note(title: "Pinned", updatedAt: date(0), isPinned: true)
        let unpinnedNew = Note(title: "Recent", updatedAt: date(500))

        let result = NoteOrganizer.organize(
            [unpinnedNew, pinnedOld],
            scope: .all,
            searchText: "",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["Pinned", "Recent"])
    }

    @Test
    func pinningIsHonoredInsideAFolder() throws {
        let context = try makeContext()
        let inbox = Folder(name: "Inbox")
        context.insert(inbox)

        let pinned = Note(title: "Pinned", updatedAt: date(0), isPinned: true, folder: inbox)
        let recent = Note(title: "Recent", updatedAt: date(500), folder: inbox)
        context.insert(pinned)
        context.insert(recent)

        let result = NoteOrganizer.organize(
            [recent, pinned],
            scope: .folder(inbox),
            searchText: "",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["Pinned", "Recent"])
    }

    @Test
    func sortingByLastUpdatedPutsNewestFirst() {
        let older = Note(title: "Older", updatedAt: date(0))
        let newer = Note(title: "Newer", updatedAt: date(100))

        let result = NoteOrganizer.organize(
            [older, newer],
            scope: .all,
            searchText: "",
            sortOption: .updated
        )

        #expect(result.map(\.title) == ["Newer", "Older"])
    }

    @Test
    func sortingByDateCreatedIgnoresEditTimes() {
        let createdFirst = Note(title: "First", createdAt: date(0), updatedAt: date(900))
        let createdSecond = Note(title: "Second", createdAt: date(100), updatedAt: date(200))

        let result = NoteOrganizer.organize(
            [createdFirst, createdSecond],
            scope: .all,
            searchText: "",
            sortOption: .created
        )

        #expect(result.map(\.title) == ["Second", "First"])
    }

    @Test
    func scopeTitlesReadNaturally() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        #expect(NoteScope.all.title == "All Notes")
        #expect(NoteScope.unfiled.title == "Unfiled")
        #expect(NoteScope.folder(folder).title == "Site Visits")
    }

    @Test
    func newNotesInheritTheBrowsedFolder() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        #expect(NoteScope.all.folder == nil)
        #expect(NoteScope.unfiled.folder == nil)
        #expect(NoteScope.folder(folder).folder?.name == "Site Visits")
    }

    @Test
    func recentNotesAreTheMostRecentlyEditedOnes() throws {
        let context = try makeContext()
        let oldest = Note(title: "Oldest", updatedAt: date(0))
        let middle = Note(title: "Middle", updatedAt: date(60))
        let newest = Note(title: "Newest", updatedAt: date(120))
        context.insert(oldest)
        context.insert(middle)
        context.insert(newest)

        let result = NoteOrganizer.recent([oldest, newest, middle], limit: 2)

        #expect(result.map(\.title) == ["Newest", "Middle"])
    }

    @Test
    func recentNotesIgnorePinning() throws {
        let context = try makeContext()
        // Pinning says a note matters. Recent answers what was worked on last,
        // which is a different question, so the pin must not reorder it.
        let pinnedButOld = Note(title: "Pinned", updatedAt: date(0), isPinned: true)
        let edited = Note(title: "Edited", updatedAt: date(60))
        context.insert(pinnedButOld)
        context.insert(edited)

        let result = NoteOrganizer.recent([pinnedButOld, edited], limit: 5)

        #expect(result.map(\.title) == ["Edited", "Pinned"])
    }
}
