//
//  CaseNotesTests.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

@MainActor
struct CaseNotesTests {
    @Test
    func noteInitializerStoresValues() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)

        let note = Note(
            title: "Meeting Notes",
            body: "Follow up on the project timeline.",
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: true,
            eventDate: eventDate
        )

        #expect(note.title == "Meeting Notes")
        #expect(note.body == "Follow up on the project timeline.")
        #expect(note.createdAt == createdAt)
        #expect(note.updatedAt == updatedAt)
        #expect(note.isPinned)
        #expect(note.eventDate == eventDate)
    }

    @Test
    func notePersistsInMemoryModelContainer() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Note.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let eventDate = Date(timeIntervalSince1970: 1_700_086_400)
        
        let note = Note(
            title: "Project Ideas",
            body: "Explore a small native iOS app.",
            isPinned: true,
            eventDate: eventDate
        )

        context.insert(note)
        try context.save()

        let fetchedNotes = try context.fetch(FetchDescriptor<Note>())

        #expect(fetchedNotes.count == 1)
        
        let fetchedNote = try #require(fetchedNotes.first)
        #expect(fetchedNote.title == "Project Ideas")
        #expect(fetchedNote.body == "Explore a small native iOS app.")
        #expect(fetchedNote.isPinned)
        #expect(fetchedNote.eventDate == eventDate)
    }
    
    @Test
    func noteDefaultsToUnpinnedWithoutEventDate() {
        let note = Note()

        #expect(note.isPinned == false)
        #expect(note.eventDate == nil)
    }
}
