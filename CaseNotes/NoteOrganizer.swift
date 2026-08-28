//
//  NoteOrganizer.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

/// Which notes the list is currently showing.
///
/// Unfiled is a first-class scope rather than a pseudo-folder, so notes never
/// need a folder in order to be found.
enum NoteScope: Hashable {
    case all
    case unfiled
    case folder(Folder)

    /// Title for the notes list showing this scope.
    var title: String {
        switch self {
        case .all: "All Notes"
        case .unfiled: "Unfiled"
        case let .folder(folder): folder.displayName
        }
    }

    /// The folder a new note should be filed into when created in this scope.
    var folder: Folder? {
        switch self {
        case .all, .unfiled: nil
        case let .folder(folder): folder
        }
    }

    /// Whether a note belongs in this scope.
    ///
    /// Folders are compared by persistent identity rather than by object
    /// identity, so a note still matches after its folder has been refetched
    /// into another context.
    ///
    /// - Parameter note: The note to test.
    /// - Returns: `true` when the note should appear in this scope.
    func contains(_ note: Note) -> Bool {
        switch self {
        case .all:
            true
        case .unfiled:
            note.folder == nil
        case let .folder(folder):
            note.folder?.persistentModelID == folder.persistentModelID
        }
    }
}

/// How the notes list is ordered.
enum NoteSortOption: String, CaseIterable, Identifiable {
    case updated = "Last Updated"
    case created = "Date Created"

    var id: Self { self }
}

/// Filtering and ordering for the notes list.
///
/// Kept apart from the views so the rules that decide what a user sees, and in
/// what order, can be tested directly.
enum NoteOrganizer {
    /// Narrows notes to a scope and a search term, then orders them.
    ///
    /// Pinned notes always sort ahead of unpinned ones, whichever ordering is
    /// chosen, so pinning stays predictable inside every folder.
    ///
    /// - Parameters:
    ///   - notes: Every note available to the view.
    ///   - scope: The folder or pseudo-folder being browsed.
    ///   - searchText: Text to match against titles and bodies. Whitespace only
    ///     or empty means no filtering.
    ///   - sortOption: The ordering to apply within each pinned group.
    /// - Returns: The notes to display, in display order.
    static func organize(
        _ notes: [Note],
        scope: NoteScope,
        searchText: String,
        sortOption: NoteSortOption
    ) -> [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = notes.filter { note in
            guard scope.contains(note) else {
                return false
            }

            guard !query.isEmpty else {
                return true
            }

            return note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }

            switch sortOption {
            case .updated:
                return lhs.updatedAt > rhs.updatedAt
            case .created:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}
