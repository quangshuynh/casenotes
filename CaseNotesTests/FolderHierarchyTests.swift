//
//  FolderHierarchyTests.swift
//  CaseNotesTests
//
//  Created by q on 8/29/26.
//

import Foundation
import SwiftData
import Testing
@testable import CaseNotes

/// Covers the rules that keep the folder graph a tree: what may move where,
/// what deleting a folder does to the things inside it, and how a location is
/// derived from the parent chain rather than stored.
@MainActor
struct FolderHierarchyTests {
    /// A fresh in-memory store holding the app's full model graph.
    ///
    /// The whole graph rather than a subset, because deletion has to be able to
    /// show that notes, drawings, and revisions are left alone.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self, NoteRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Inserts a folder, optionally inside another.
    @discardableResult
    private func folder(
        _ name: String,
        in parent: Folder? = nil,
        context: ModelContext
    ) -> Folder {
        let folder = Folder(name: name, parent: parent)
        context.insert(folder)
        return folder
    }

    // MARK: Traversal

    @Test
    func rootFolderHasNoAncestors() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)

        #expect(work.isRoot)
        #expect(FolderHierarchy.ancestors(of: work).isEmpty)
    }

    @Test
    func ancestorsRunFromTheNearestFolderOutwards() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)
        try context.save()

        #expect(FolderHierarchy.ancestors(of: research).map(\.name) == ["Project Alpha", "Work"])
    }

    @Test
    func descendantsCoverEveryDepth() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        folder("Research", in: alpha, context: context)
        folder("Meetings", in: alpha, context: context)
        folder("Project Beta", in: work, context: context)
        try context.save()

        let names = Set(FolderHierarchy.descendants(of: work).map(\.name))

        #expect(names == ["Project Alpha", "Project Beta", "Research", "Meetings"])
        #expect(FolderHierarchy.descendants(of: work).count == 4)
    }

    @Test
    func aFolderIsNotItsOwnDescendant() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        try context.save()

        #expect(FolderHierarchy.isDescendant(alpha, of: work))
        #expect(FolderHierarchy.isDescendant(work, of: work) == false)
        #expect(FolderHierarchy.isDescendant(work, of: alpha) == false)
    }

    /// SwiftData accepts a self-referential graph that is not a tree, so
    /// traversal has to terminate on data the app would never have written.
    ///
    /// The cycle is built by assigning two folders as each other's parent,
    /// which the store allows and which no path through the app can produce.
    @Test
    func traversalTerminatesOnAMalformedCycle() throws {
        let context = try makeContext()
        let first = folder("First", context: context)
        let second = folder("Second", context: context)

        first.parent = second
        second.parent = first

        #expect(FolderHierarchy.ancestors(of: first).count == 1)
        #expect(FolderHierarchy.descendants(of: first).count == 1)
        #expect(FolderHierarchy.isDescendant(second, of: first))
        #expect(FolderHierarchy.pathComponents(of: first) == ["Second", "First"])
    }

    // MARK: Cycle prevention

    @Test
    func aFolderCannotMoveIntoItself() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        try context.save()

        #expect(FolderHierarchy.canMove(work, to: work) == false)
        #expect(FolderHierarchy.move(work, to: work) == false)
        #expect(work.parent == nil)
    }

    @Test
    func aFolderCannotMoveIntoItsOwnChild() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        try context.save()

        #expect(FolderHierarchy.canMove(work, to: alpha) == false)
        #expect(FolderHierarchy.move(work, to: alpha) == false)
        #expect(work.parent == nil)
        #expect(alpha.parent?.name == "Work")
    }

    @Test
    func aFolderCannotMoveIntoADeeperDescendant() throws {
        let context = try makeContext()
        let first = folder("A", context: context)
        let second = folder("B", in: first, context: context)
        let third = folder("C", in: second, context: context)
        try context.save()

        #expect(FolderHierarchy.canMove(first, to: third) == false)
        #expect(FolderHierarchy.move(first, to: third) == false)
        #expect(first.parent == nil)
        #expect(third.parent?.name == "B")
    }

    @Test
    func movingBetweenSiblingsSucceeds() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let personal = folder("Personal", context: context)
        let journal = folder("Journal", in: work, context: context)
        try context.save()

        #expect(FolderHierarchy.canMove(journal, to: personal))
        #expect(FolderHierarchy.move(journal, to: personal))
        try context.save()

        #expect(journal.parent?.name == "Personal")
        #expect(work.children.isEmpty)
        #expect(personal.children.map(\.name) == ["Journal"])
    }

    @Test
    func movingBackToRootSucceeds() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        try context.save()

        #expect(FolderHierarchy.canMove(alpha, to: nil))
        #expect(FolderHierarchy.move(alpha, to: nil))
        try context.save()

        #expect(alpha.isRoot)
        #expect(work.children.isEmpty)
    }

    @Test
    func movingAFolderCarriesItsSubtree() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let personal = folder("Personal", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)
        try context.save()

        FolderHierarchy.move(alpha, to: personal)
        try context.save()

        #expect(research.parent?.name == "Project Alpha")
        #expect(FolderHierarchy.pathComponents(of: research) == ["Personal", "Project Alpha", "Research"])
    }

    /// Moving a folder is organization, so nothing a note carries may move
    /// with it.
    @Test
    func movingAFolderLeavesItsNotesUntouched() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let personal = folder("Personal", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)

        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(title: "Kickoff", body: "Agenda.", updatedAt: editedAt, folder: alpha)
        context.insert(note)
        try context.save()

        FolderHierarchy.move(alpha, to: personal)
        try context.save()

        #expect(note.folder?.name == "Project Alpha")
        #expect(note.updatedAt == editedAt)
        #expect(note.title == "Kickoff")
        #expect(note.body == "Agenda.")
        #expect(note.revisions.isEmpty)
    }

    /// Renaming an ancestor changes what a descendant's location reads as, and
    /// nothing about the notes inside it.
    @Test
    func renamingAnAncestorLeavesNotesUntouched() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)

        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(title: "Kickoff", updatedAt: editedAt, folder: alpha)
        context.insert(note)
        try context.save()

        work.name = "Client Work"
        try context.save()

        #expect(FolderHierarchy.pathText(of: alpha) == "Client Work › Project Alpha")
        #expect(note.updatedAt == editedAt)
        #expect(note.revisions.isEmpty)
    }

    // MARK: Deleting

    /// The whole promotion rule in one case: A over B over C, with notes filed
    /// directly in B and deeper in C.
    @Test
    func deletingAMiddleFolderPromotesChildrenAndUnfilesItsOwnNotes() throws {
        let context = try makeContext()
        let first = folder("A", context: context)
        let second = folder("B", in: first, context: context)
        let third = folder("C", in: second, context: context)

        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let direct = Note(title: "In B", body: "Kept.", updatedAt: editedAt, folder: second)
        let deeper = Note(title: "In C", body: "Untouched.", updatedAt: editedAt, folder: third)
        context.insert(direct)
        context.insert(deeper)
        try context.save()

        FolderHierarchy.delete(second, in: context)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(Set(folders.map(\.name)) == ["A", "C"])
        #expect(third.parent?.name == "A")
        #expect(first.children.map(\.name) == ["C"])

        #expect(notes.count == 2)
        #expect(direct.folder == nil)
        #expect(deeper.folder?.name == "C")

        // Deleting a folder organizes rather than edits.
        #expect(direct.updatedAt == editedAt)
        #expect(deeper.updatedAt == editedAt)
        #expect(direct.title == "In B")
        #expect(direct.body == "Kept.")
        #expect(direct.revisions.isEmpty)
        #expect(deeper.revisions.isEmpty)

        let revisions = try context.fetch(FetchDescriptor<NoteRevision>())
        #expect(revisions.isEmpty)
    }

    @Test
    func deletingARootFolderMakesItsChildrenRoots() throws {
        let context = try makeContext()
        let second = folder("B", context: context)
        let third = folder("C", in: second, context: context)
        let fourth = folder("D", in: second, context: context)

        let direct = Note(title: "In B", folder: second)
        context.insert(direct)
        try context.save()

        FolderHierarchy.delete(second, in: context)
        try context.save()

        #expect(third.isRoot)
        #expect(fourth.isRoot)
        #expect(direct.folder == nil)
        #expect(try context.fetch(FetchDescriptor<Folder>()).count == 2)
    }

    /// Deleting a folder never reaches a note's drawing or its history, which
    /// belong to the note rather than to where it is filed.
    @Test
    func deletingAFolderKeepsDrawingsAndRevisions() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)

        let note = Note(title: "Site Visit", folder: work)
        let drawing = NoteDrawing(data: Data([0x01, 0x02]))
        let revision = NoteRevision(title: "Site Visit", body: "Earlier text.")
        context.insert(note)
        context.insert(drawing)
        context.insert(revision)
        note.drawing = drawing
        revision.note = note
        try context.save()

        FolderHierarchy.delete(work, in: context)
        try context.save()

        #expect(note.folder == nil)
        #expect(note.drawing?.data == Data([0x01, 0x02]))
        #expect(NoteHistory.revisions(of: note).count == 1)
        #expect(try context.fetch(FetchDescriptor<NoteDrawing>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NoteRevision>()).count == 1)
    }

    @Test
    func deletingALeafFolderLeavesTheRestOfTheTreeAlone() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let beta = folder("Project Beta", in: work, context: context)
        try context.save()

        FolderHierarchy.delete(alpha, in: context)
        try context.save()

        #expect(beta.parent?.name == "Work")
        #expect(work.children.map(\.name) == ["Project Beta"])
    }

    // MARK: Creation

    @Test
    func creatingAFolderWithoutAParentCreatesARootFolder() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        try context.save()

        #expect(work.parent == nil)
        #expect(work.isRoot)
    }

    @Test
    func creatingAFolderInsideAnotherRecordsItsParent() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        try context.save()

        #expect(alpha.parent?.persistentModelID == work.persistentModelID)
        #expect(work.children.map(\.name) == ["Project Alpha"])
    }

    /// A note started while browsing a nested folder lands in that exact
    /// folder, and creating it still records nothing in version history.
    @Test
    func creatingANoteInANestedFolderFilesItThereWithoutARevision() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)
        try context.save()

        let draft = NoteDraft(title: "Interview", body: "Notes.", folder: research)
        let note = draft.insertNote(into: context)
        try context.save()

        #expect(note.folder?.name == "Research")
        #expect(FolderHierarchy.pathComponents(of: research) == ["Work", "Project Alpha", "Research"])
        #expect(note.revisions.isEmpty)
        #expect(try context.fetch(FetchDescriptor<NoteRevision>()).isEmpty)
    }

    // MARK: Paths

    @Test
    func aRootFolderPathIsJustItsName() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        try context.save()

        #expect(FolderHierarchy.pathText(of: work) == "Work")
        #expect(FolderHierarchy.locationText(of: work) == nil)
        #expect(FolderHierarchy.spokenLocation(of: work) == nil)
    }

    @Test
    func aNestedFolderPathNamesEveryFolderAboveIt() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)
        try context.save()

        #expect(FolderHierarchy.pathText(of: research) == "Work › Project Alpha › Research")
        #expect(FolderHierarchy.locationText(of: research) == "Work › Project Alpha")
        #expect(FolderHierarchy.spokenLocation(of: research) == "inside Work, Project Alpha")
    }

    /// The path is derived from the parent chain on every read, so a rename
    /// anywhere above a folder shows up without anything being rewritten.
    @Test
    func aPathFollowsRenamesAndMoves() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let personal = folder("Personal", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)
        try context.save()

        work.name = "Client Work"
        try context.save()
        #expect(FolderHierarchy.pathText(of: research) == "Client Work › Project Alpha › Research")

        FolderHierarchy.move(alpha, to: personal)
        try context.save()
        #expect(FolderHierarchy.pathText(of: research) == "Personal › Project Alpha › Research")

        FolderHierarchy.move(research, to: nil)
        try context.save()
        #expect(FolderHierarchy.pathText(of: research) == "Research")
    }

    @Test
    func aDeepPathIsShortenedFromTheFront() throws {
        let context = try makeContext()
        var current: Folder?

        for name in ["One", "Two", "Three", "Four", "Five"] {
            current = folder(name, in: current, context: context)
        }

        let deepest = try #require(current)
        try context.save()

        #expect(FolderHierarchy.pathComponents(of: deepest).count == 5)
        #expect(FolderHierarchy.pathText(of: deepest) == "… › Three › Four › Five")
        #expect(FolderHierarchy.pathText(of: deepest, maximumComponents: 5) == "One › Two › Three › Four › Five")
    }

    @Test
    func unnamedFoldersUseThePlaceholderInAPath() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let unnamed = folder("   ", in: work, context: context)
        try context.save()

        #expect(FolderHierarchy.pathText(of: unnamed) == "Work › Untitled Folder")
    }

    // MARK: Tree and destinations

    @Test
    func theTreeGroupsFoldersByWhereTheySit() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let personal = folder("Personal", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        folder("Project Beta", in: work, context: context)
        folder("Research", in: alpha, context: context)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let tree = FolderTree(folders)

        #expect(tree.roots.map(\.name) == ["Personal", "Work"])
        #expect(tree.children(of: work).map(\.name) == ["Project Alpha", "Project Beta"])
        #expect(tree.childCount(of: work) == 2)
        #expect(tree.childCount(of: alpha) == 1)
        #expect(tree.childCount(of: personal) == 0)
    }

    @Test
    func destinationsReadInTreeOrderWithTheirDepthAndPath() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        folder("Research", in: alpha, context: context)
        folder("Personal", context: context)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let destinations = FolderTree(folders).destinations()

        #expect(destinations.map(\.name) == ["Personal", "Work", "Project Alpha", "Research"])
        #expect(destinations.map(\.depth) == [0, 0, 1, 2])
        #expect(destinations.last?.pathText == "Work › Project Alpha › Research")
        #expect(destinations.last?.spokenDescription == "Research, inside Work, Project Alpha")
        #expect(destinations.first?.spokenDescription == "Personal, top level")
    }

    /// The destinations a folder may move to are exactly the ones that keep the
    /// graph a tree, which is why the picker and the validation agree.
    @Test
    func destinationsLeaveOutTheMovingFolderAndItsSubtree() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        folder("Research", in: alpha, context: context)
        folder("Personal", context: context)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let offered = FolderTree(folders).destinations(excludingSubtreeOf: alpha)

        #expect(offered.map(\.name) == ["Personal", "Work"])

        for destination in offered {
            #expect(FolderHierarchy.canMove(alpha, to: destination.folder))
        }
    }

    @Test
    func foldersSharingANameKeepAStableOrder() throws {
        let context = try makeContext()
        let earlier = Folder(
            name: "Archive",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = Folder(
            name: "Archive",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        context.insert(later)
        context.insert(earlier)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let ordered = FolderTree(folders).roots

        #expect(ordered.count == 2)
        #expect(ordered.first?.createdAt == earlier.createdAt)
    }

    // MARK: Counts and scopes

    /// A folder row counts what opening it shows, which is the notes filed in
    /// that folder itself.
    @Test
    func aFolderCountExcludesNotesInItsSubfolders() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)

        context.insert(Note(title: "Direct", folder: work))
        context.insert(Note(title: "Nested", folder: alpha))
        context.insert(Note(title: "Loose"))
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        let counts = ScopeCounts(notes: notes)

        #expect(counts.count(for: .folder(work)) == 1)
        #expect(counts.count(for: .folder(alpha)) == 1)
        #expect(counts.count(for: .all) == 3)
        #expect(counts.count(for: .unfiled) == 1)
    }

    /// All Notes is global and Unfiled means no folder at all, neither of which
    /// nesting changes.
    @Test
    func allNotesIncludesNestedNotesAndUnfiledExcludesThem() throws {
        let context = try makeContext()
        let work = folder("Work", context: context)
        let alpha = folder("Project Alpha", in: work, context: context)
        let research = folder("Research", in: alpha, context: context)

        let deep = Note(title: "Deep", folder: research)
        let loose = Note(title: "Loose")
        context.insert(deep)
        context.insert(loose)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(NoteScope.all.contains(deep))
        #expect(NoteScope.unfiled.contains(deep) == false)
        #expect(NoteScope.unfiled.contains(loose))

        // A folder scope holds only what is filed in it directly.
        #expect(NoteScope.folder(work).contains(deep) == false)
        #expect(NoteScope.folder(research).contains(deep))

        let all = NoteOrganizer.organize(
            notes,
            scope: .all,
            searchText: "",
            sortOption: .updated
        )
        #expect(all.count == 2)
    }
}
