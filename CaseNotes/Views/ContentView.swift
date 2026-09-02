//
//  ContentView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

/// The app's browsing shell.
///
/// Folders are the root, and a scope pushes to the notes it holds, which then
/// pushes to a note. A plain stack was chosen over a split view because the
/// collapsed split view on iPhone hides the notes list title and complicates
/// selection state around folder deletion, neither of which pays for itself in
/// an app that is used in portrait on a phone.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            FolderListView()
        }
        // An edit that ended without a Save or a Cancel, because the app was
        // killed or the device ran out of room, leaves its imported files in
        // staging with no editor left to discard them. Nothing there outlives a
        // launch, so the directory is cleared before browsing begins.
        .task {
            AttachmentStore.shared.purgeStaging()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}
