//
//  Folder.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

/// A named grouping of notes.
///
/// Folders are organizational only. A note is complete without one, and the
/// absence of a folder is a real state rather than a missing value: those notes
/// are shown as Unfiled.
@Model
final class Folder {
    var name: String
    var createdAt: Date

    /// Notes filed here.
    ///
    /// The nullify delete rule is the important part: removing a folder must
    /// never destroy writing. Deleting a folder clears this side of the
    /// relationship and leaves every note in place, unfiled.
    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note] = []

    init(
        name: String = "",
        createdAt: Date = Date()
    ) {
        self.name = name
        self.createdAt = createdAt
    }

    /// The name to display, falling back to a placeholder for unnamed folders.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Folder" : trimmed
    }
}
