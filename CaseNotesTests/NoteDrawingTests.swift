//
//  NoteDrawingTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import PencilKit
import SwiftData
import Testing
@testable import CaseNotes

@MainActor
struct NoteDrawingTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A drawing with a single straight stroke.
    ///
    /// Built in code rather than captured from a device so the tests stay
    /// self-contained and free of recorded fixtures.
    private func makeDrawing(strokes: Int = 1) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)

        let strokeList = (0..<strokes).map { index -> PKStroke in
            let offset = Double(index) * 20
            let points = [
                PKStrokePoint(
                    location: CGPoint(x: offset, y: 0),
                    timeOffset: 0,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: 0
                ),
                PKStrokePoint(
                    location: CGPoint(x: offset + 40, y: 60),
                    timeOffset: 0.1,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: 0
                ),
            ]

            return PKStroke(
                ink: ink,
                path: PKStrokePath(controlPoints: points, creationDate: Date())
            )
        }

        return PKDrawing(strokes: strokeList)
    }

    // MARK: Serialization

    @Test
    func encodingAnEmptyDrawingYieldsNothing() {
        #expect(DrawingCodec.encode(PKDrawing()) == nil)
    }

    @Test
    func drawingsSurviveAnEncodeDecodeRoundTrip() throws {
        let drawing = makeDrawing(strokes: 3)
        let data = try #require(DrawingCodec.encode(drawing))

        let restored = DrawingCodec.decode(data)

        #expect(restored.strokes.count == 3)
        #expect(restored.bounds.isEmpty == false)
    }

    @Test
    func corruptDataDecodesToAnEmptyDrawing() {
        let restored = DrawingCodec.decode(Data("not a drawing".utf8))

        #expect(restored.strokes.isEmpty)
    }

    // MARK: Attaching and removing

    @Test
    func applyingADrawingAttachesItAndStampsTheNote() throws {
        let context = try makeContext()
        let note = Note(
            title: "North Wing",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        context.insert(note)

        let editedAt = Date(timeIntervalSince1970: 1_700_500_000)
        let didChange = NoteDrawing.apply(
            makeDrawing(),
            to: note,
            in: context,
            at: editedAt
        )

        #expect(didChange)
        #expect(note.drawing != nil)
        #expect(note.updatedAt == editedAt)
        #expect(note.drawing?.updatedAt == editedAt)
    }

    @Test
    func applyingAnEmptyDrawingToANoteWithoutOneChangesNothing() throws {
        let context = try makeContext()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let note = Note(title: "North Wing", updatedAt: updatedAt)
        context.insert(note)

        let didChange = NoteDrawing.apply(PKDrawing(), to: note, in: context)

        #expect(didChange == false)
        #expect(note.drawing == nil)
        #expect(note.updatedAt == updatedAt)
    }

    @Test
    func clearingADrawingRemovesTheRecord() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing")
        context.insert(note)
        NoteDrawing.apply(makeDrawing(), to: note, in: context)
        try context.save()

        let didChange = NoteDrawing.apply(PKDrawing(), to: note, in: context)
        try context.save()

        #expect(didChange)
        #expect(note.drawing == nil)
        #expect(try context.fetch(FetchDescriptor<NoteDrawing>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    @Test
    func reapplyingTheSameDrawingIsANoOp() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing")
        context.insert(note)

        let drawing = makeDrawing()
        NoteDrawing.apply(drawing, to: note, in: context)

        let updatedAt = note.updatedAt
        let didChange = NoteDrawing.apply(
            drawing,
            to: note,
            in: context,
            at: Date(timeIntervalSince1970: 1_700_900_000)
        )

        #expect(didChange == false)
        #expect(note.updatedAt == updatedAt)
    }

    /// Documents the platform behavior that shapes the drawing editor.
    ///
    /// PencilKit serializes a given drawing object identically every time, but
    /// decoding and re-encoding produces different bytes. Stored data therefore
    /// cannot be compared to a freshly encoded canvas to decide whether the user
    /// changed anything, which is why the editor tracks edits through the canvas
    /// delegate instead.
    @Test
    func serializationIsStablePerObjectButNotAcrossARoundTrip() throws {
        let drawing = makeDrawing()

        let first = try #require(DrawingCodec.encode(drawing))
        let again = try #require(DrawingCodec.encode(drawing))
        let afterRoundTrip = try #require(
            DrawingCodec.encode(DrawingCodec.decode(first))
        )

        #expect(first == again)
        #expect(first != afterRoundTrip)
        #expect(DrawingCodec.decode(afterRoundTrip).strokes.count == drawing.strokes.count)
    }

    @Test
    func replacingADrawingUpdatesTheExistingRecord() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing")
        context.insert(note)
        NoteDrawing.apply(makeDrawing(strokes: 1), to: note, in: context)
        try context.save()

        NoteDrawing.apply(makeDrawing(strokes: 4), to: note, in: context)
        try context.save()

        let records = try context.fetch(FetchDescriptor<NoteDrawing>())
        let data = try #require(note.drawing?.data)

        #expect(records.count == 1)
        #expect(DrawingCodec.decode(data).strokes.count == 4)
    }

    // MARK: Persistence

    @Test
    func drawingsPersistAndRefetch() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing")
        context.insert(note)
        NoteDrawing.apply(makeDrawing(strokes: 2), to: note, in: context)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        let fetched = try #require(notes.first)
        let data = try #require(fetched.drawing?.data)

        #expect(DrawingCodec.decode(data).strokes.count == 2)
    }

    @Test
    func drawingsSurviveReopeningTheStore() throws {
        let url = URL.temporaryDirectory
            .appending(path: "casenotes-drawing-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let container = try ModelContainer(
                for: Note.self, Folder.self, NoteDrawing.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            let note = Note(title: "North Wing")
            context.insert(note)
            NoteDrawing.apply(makeDrawing(strokes: 2), to: note, in: context)
            try context.save()
        }

        let container = try ModelContainer(
            for: Note.self, Folder.self, NoteDrawing.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        let notes = try context.fetch(FetchDescriptor<Note>())
        let data = try #require(notes.first?.drawing?.data)

        #expect(DrawingCodec.decode(data).strokes.count == 2)
    }

    @Test
    func deletingANoteDeletesItsDrawing() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing")
        context.insert(note)
        NoteDrawing.apply(makeDrawing(), to: note, in: context)
        try context.save()

        context.delete(note)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<NoteDrawing>()).isEmpty)
    }

    @Test
    func deletingAFolderLeavesFiledDrawingsIntact() throws {
        let context = try makeContext()
        let folder = Folder(name: "Site Visits")
        context.insert(folder)

        let note = Note(title: "North Wing", folder: folder)
        context.insert(note)
        NoteDrawing.apply(makeDrawing(), to: note, in: context)
        try context.save()

        context.delete(folder)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)
        #expect(notes.first?.folder == nil)
        #expect(notes.first?.drawing != nil)
    }

    // MARK: Export

    @Test
    func exportsNoteThatADrawingIsNotIncluded() throws {
        let context = try makeContext()
        let note = Note(title: "North Wing", body: "Walked the wing.")
        context.insert(note)
        NoteDrawing.apply(makeDrawing(), to: note, in: context)

        let export = NoteExport.markdown(for: note, includingAttribution: false)

        #expect(export.contains(NoteExport.drawingNotice))
    }

    @Test
    func exportsOfTextOnlyNotesMentionNoDrawing() {
        let note = Note(title: "North Wing", body: "Walked the wing.")

        let export = NoteExport.markdown(for: note, includingAttribution: false)

        #expect(!export.localizedCaseInsensitiveContains("drawing"))
    }
}
