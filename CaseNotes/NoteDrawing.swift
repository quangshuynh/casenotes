//
//  NoteDrawing.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import PencilKit
import SwiftData

/// The drawing attached to a note, stored as PencilKit's own serialized form.
///
/// Drawings live in their own model rather than as a property on `Note` for one
/// reason: size. A sketch is orders of magnitude larger than the text around it,
/// and browsing a list of notes should never pay to load one. As a separate
/// entity behind a relationship the bytes stay faulted out until a note is
/// actually opened, and `externalStorage` keeps them out of the database file
/// entirely.
@Model
final class NoteDrawing {
    /// PencilKit's serialized drawing, as produced by `dataRepresentation()`.
    @Attribute(.externalStorage)
    var data: Data

    var updatedAt: Date

    /// The note this drawing belongs to.
    ///
    /// The owning side is `Note.drawing`, which cascades, so a drawing never
    /// outlives its note.
    var note: Note?

    init(
        data: Data = Data(),
        updatedAt: Date = Date()
    ) {
        self.data = data
        self.updatedAt = updatedAt
    }
}

extension NoteDrawing {
    /// Writes a canvas drawing to a note, creating, updating, or removing the
    /// stored record as needed.
    ///
    /// Clearing a canvas and saving removes the record rather than storing an
    /// empty one, so "no drawing" has exactly one representation. A drawing is
    /// authored content, so a change here moves the note's edit timestamp, in
    /// contrast to filing.
    ///
    /// - Parameters:
    ///   - drawing: The canvas contents to store.
    ///   - note: The note to attach the drawing to.
    ///   - context: The context that owns the note, used to insert or delete the
    ///     drawing record.
    ///   - date: Timestamp recorded on the note and drawing. Injectable for tests.
    /// - Returns: `true` when the note was changed.
    @discardableResult
    static func apply(
        _ drawing: PKDrawing,
        to note: Note,
        in context: ModelContext,
        at date: Date = Date()
    ) -> Bool {
        let encoded = DrawingCodec.encode(drawing)

        switch (encoded, note.drawing) {
        case (nil, nil):
            return false

        case let (nil, .some(existing)):
            note.drawing = nil
            context.delete(existing)
            note.updatedAt = date
            return true

        case let (.some(data), nil):
            let record = NoteDrawing(data: data, updatedAt: date)
            context.insert(record)
            note.drawing = record
            note.updatedAt = date
            return true

        case let (.some(data), .some(existing)):
            guard existing.data != data else {
                return false
            }

            existing.data = data
            existing.updatedAt = date
            note.updatedAt = date
            return true
        }
    }
}

/// Converts between PencilKit drawings and the bytes that get persisted.
///
/// Kept separate from the model so the encoding rules, including what counts as
/// an empty drawing and how corrupt data is handled, can be tested directly.
enum DrawingCodec {
    /// Serializes a drawing for storage.
    ///
    /// - Parameter drawing: The drawing to encode.
    /// - Returns: The serialized drawing, or `nil` when it has no strokes.
    static func encode(_ drawing: PKDrawing) -> Data? {
        guard !drawing.strokes.isEmpty else {
            return nil
        }

        return drawing.dataRepresentation()
    }

    /// Restores a drawing from stored bytes.
    ///
    /// Unreadable data yields an empty drawing rather than an error. A sketch
    /// that cannot be decoded should leave the rest of the note usable.
    ///
    /// - Parameter data: Previously serialized drawing data.
    /// - Returns: The decoded drawing, or an empty drawing if decoding fails.
    static func decode(_ data: Data) -> PKDrawing {
        (try? PKDrawing(data: data)) ?? PKDrawing()
    }
}
