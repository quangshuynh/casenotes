//
//  CaseNotesApp.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

@main
struct CaseNotesApp: App {
    var body: some Scene {
        WindowGroup {
            AppLockView()
        }
        .modelContainer(
            for: [Note.self, Folder.self, NoteDrawing.self, NoteRevision.self]
        )
    }
}
