//
//  NoteHistory.swift
//  CaseNotes
//
//  Created by q on 8/28/26.
//

import Foundation
import SwiftData

/// The rules behind a note's version history: when a previous state is kept,
/// what order history reads in, and what restoring one does.
///
/// Every write that can add a version goes through here, so there is one answer
/// to "does this produce a new version" rather than one answer per screen. The
/// timestamp rules stay in ``NoteDraft``, which this type calls rather than
/// reimplements.
///
/// The current note is always the newest version. History holds only states that
/// have been replaced, which is why saving a brand new note records nothing:
/// there is no earlier state to recover.
enum NoteHistory {
    /// A note's previous states, newest first.
    ///
    /// SwiftData guarantees nothing about the order of a relationship array, so
    /// the order is established here instead. Ties are broken all the way down
    /// to the writing itself, so two versions captured in the same instant
    /// always list in the same order rather than shuffling between updates.
    ///
    /// - Parameter note: The note whose history is being read.
    /// - Returns: The revisions, most recently replaced first.
    static func revisions(of note: Note) -> [NoteRevision] {
        note.revisions.sorted(by: isOrderedBefore)
    }

    /// Applies an edited draft to a note, keeping the state it replaces.
    ///
    /// This is the save path for an existing note. Creating a note applies its
    /// draft directly instead: a new note has no earlier state, and recording
    /// one would put a version in history that never existed.
    ///
    /// A version is written only when the authored content actually changes, so
    /// saving an untouched note, or one where only the folder moved, leaves
    /// history alone.
    ///
    /// - Parameters:
    ///   - draft: The contents confirmed by the user.
    ///   - note: The persistent note to update in place.
    ///   - context: The context that owns the note, used to insert the revision.
    ///   - date: The timestamp recorded on the edit and on any revision it
    ///     creates. Injectable so tests can assert on an exact value.
    /// - Returns: `true` when the note was modified in any way.
    @discardableResult
    static func save(
        _ draft: NoteDraft,
        to note: Note,
        in context: ModelContext,
        at date: Date = Date()
    ) -> Bool {
        if draft.hasContentChanges(comparedTo: note) {
            preserveCurrentState(of: note, in: context, at: date)
        }

        return draft.apply(to: note, at: date)
    }

    /// Makes a previous state current again.
    ///
    /// Restoring is a new edit rather than a rewind: the state being replaced is
    /// kept first, so the version the user was looking at a moment ago stays
    /// recoverable and nothing later in history is discarded. The revision
    /// itself is left untouched and stays in the list.
    ///
    /// Restoring a version the note already matches does nothing, so repeatedly
    /// restoring the same state cannot fill history with copies of it.
    ///
    /// Drawings are outside version history, so the note keeps whichever sketch
    /// it currently has.
    ///
    /// - Parameters:
    ///   - revision: The state to make current.
    ///   - note: The note to restore into.
    ///   - context: The context that owns the note, used to insert the revision
    ///     recording the state being replaced.
    ///   - date: The timestamp recorded as the edit time. Injectable for tests.
    /// - Returns: `true` when the note changed.
    @discardableResult
    static func restore(
        _ revision: NoteRevision,
        to note: Note,
        in context: ModelContext,
        at date: Date = Date()
    ) -> Bool {
        guard !revision.matchesAuthoredState(of: note) else {
            return false
        }

        preserveCurrentState(of: note, in: context, at: date)

        note.title = revision.title
        note.body = revision.body
        note.eventDate = revision.eventDate
        note.updatedAt = date

        return true
    }

    /// Writes the note's current authored state into its history.
    ///
    /// Called only from paths that have established the state is about to be
    /// replaced, which is what keeps history free of entries that duplicate the
    /// version following them.
    ///
    /// - Parameters:
    ///   - note: The note whose current state is being preserved.
    ///   - context: The context to insert the revision into.
    ///   - date: The capture time.
    /// - Returns: The revision that was recorded.
    @discardableResult
    private static func preserveCurrentState(
        of note: Note,
        in context: ModelContext,
        at date: Date
    ) -> NoteRevision {
        let revision = NoteRevision(
            title: note.title,
            body: note.body,
            eventDate: note.eventDate,
            updatedAt: note.updatedAt,
            capturedAt: date
        )

        context.insert(revision)
        revision.note = note

        return revision
    }

    /// Orders two revisions newest first.
    ///
    /// - Parameters:
    ///   - lhs: A revision.
    ///   - rhs: The revision to compare it against.
    /// - Returns: `true` when `lhs` belongs above `rhs`.
    private static func isOrderedBefore(
        _ lhs: NoteRevision,
        _ rhs: NoteRevision
    ) -> Bool {
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }

        return lhs.body < rhs.body
    }
}
