//
//  Note.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftData

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool = false
    var eventDate: Date?

    /// The folder this note is filed in, or `nil` when it is unfiled.
    ///
    /// Optional by design. Filing is never required, and it is what lets notes
    /// outlive the folder they were in.
    var folder: Folder?

    init(
        title: String = "",
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        eventDate: Date? = nil,
        folder: Folder? = nil
    ) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.eventDate = eventDate
        self.folder = folder
    }
}
