//
//  Folder.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

/// A named grouping of notes, which may itself sit inside another folder.
///
/// Folders are organizational only. A note is complete without one, and the
/// absence of a folder is a real state rather than a missing value: those notes
/// are shown as Unfiled.
///
/// Folders form a tree. A folder with no ``parent`` is a root folder, and the
/// library itself is the conceptual root, so there is no stored record standing
/// in for it. The tree invariant, cycle checks included, is enforced by
/// ``FolderHierarchy`` rather than by the store, because SwiftData will happily
/// persist a self-referential graph that is not a tree.
@Model
final class Folder {
    var name: String
    var createdAt: Date

    /// Notes filed here.
    ///
    /// Direct membership only: a note filed in a child folder belongs to that
    /// child, not to this one. The nullify delete rule is the important part:
    /// removing a folder must never destroy writing. Deleting a folder clears
    /// this side of the relationship and leaves every note in place, unfiled.
    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note] = []

    /// The folder this one sits inside, or `nil` when it is a root folder.
    ///
    /// Optional by design, and the only stored expression of hierarchy. A
    /// display path is derived by walking this chain rather than persisted,
    /// so renaming or moving an ancestor cannot leave a stale copy behind.
    var parent: Folder?

    /// Folders filed directly inside this one, in no guaranteed order.
    ///
    /// Nullify rather than cascade, deliberately: deleting a folder must not
    /// take an organization tree with it. The product behavior goes further and
    /// promotes children to the deleted folder's own parent, which
    /// ``FolderHierarchy/delete(_:in:)`` does before the delete so the rule here
    /// is only the floor rather than the mechanism.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    var children: [Folder] = []

    init(
        name: String = "",
        createdAt: Date = Date(),
        parent: Folder? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.parent = parent
    }

    /// The name to display, falling back to a placeholder for unnamed folders.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Folder" : trimmed
    }

    /// Whether this folder sits at the top level of the library.
    var isRoot: Bool {
        parent == nil
    }
}
