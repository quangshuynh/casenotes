//
//  NoteComposition.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import Foundation

/// A note about to be written, and the folder it will be filed in.
///
/// Presenting the editor with `sheet(isPresented:)` and reading the folder from
/// a second piece of state does not work: the content closure can run before
/// that state lands, and ``NoteEditorView`` seeds its draft through
/// `State(initialValue:)`, which keeps whatever the first evaluation produced.
/// The result is an editor that opens on Unfiled no matter which folder it was
/// started from, and then reports unsaved changes because its draft disagrees
/// with the arguments it was given.
///
/// Carrying the folder as the sheet's item removes the race. The presentation
/// cannot begin until the value exists, and a fresh identity per presentation
/// means the editor is built once with the folder it is meant to open on.
struct NoteComposition: Identifiable {
    /// The folder the new note starts out filed in, or `nil` for Unfiled.
    let folder: Folder?

    let id = UUID()

    /// - Parameter folder: Where the note being started should be filed.
    init(in folder: Folder?) {
        self.folder = folder
    }
}
