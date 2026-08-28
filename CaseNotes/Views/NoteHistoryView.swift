//
//  NoteHistoryView.swift
//  CaseNotes
//
//  Created by q on 8/28/26.
//

import SwiftData
import SwiftUI

/// The previous versions of one note, newest first.
///
/// Browsing history never changes the note. Each row opens a read-only version,
/// and restoring is confirmed from there rather than offered as a swipe on a
/// list of dates, because putting old writing back is worth a look first.
struct NoteHistoryView: View {
    let note: Note

    var body: some View {
        // Ordering is a sort over the relationship, so it is done once per
        // update and handed to the list rather than recomputed per row.
        let revisions = NoteHistory.revisions(of: note)

        return Group {
            if revisions.isEmpty {
                emptyState
            } else {
                revisionList(revisions)
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Shown for a note that has not been edited since it was written.
    private var emptyState: some View {
        ContentUnavailableView(
            "No Previous Versions",
            systemImage: "clock.arrow.circlepath",
            description: Text(
                "Previous versions appear here after you save changes to this note."
            )
        )
    }

    /// The list of versions.
    ///
    /// - Parameter revisions: The already ordered revisions to show.
    /// - Returns: The configured list.
    private func revisionList(_ revisions: [NoteRevision]) -> some View {
        List {
            Section {
                ForEach(revisions) { revision in
                    NavigationLink {
                        NoteRevisionView(revision: revision, note: note)
                    } label: {
                        NoteRevisionRowView(revision: revision)
                    }
                    .listRowBackground(Theme.Colors.surface)
                }
            } footer: {
                Text("The note as it reads now is the current version and is not listed here.")
            }
        }
        .appCanvasBackground()
    }
}

/// One previous version summarized for the history list.
///
/// The layout follows the notes list: title, a short preview, then one quiet
/// metadata line. The preview is the plain-text form rather than rendered
/// Markdown, so showing a long history costs no parsing beyond the opening of
/// each body.
private struct NoteRevisionRowView: View {
    let revision: NoteRevision

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text(revision.displayTitle)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)

            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityLabel("Edited \(formattedDate)")
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }

    /// When this version was written, which is what tells two versions apart.
    ///
    /// The time is included because versions of the same note are often minutes
    /// rather than days apart.
    private var formattedDate: String {
        revision.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// A short plain-text preview of the version's body.
    private var preview: String {
        MarkdownDocument.plainPreview(of: revision.body)
    }
}

#Preview("History") {
    NavigationStack {
        NoteHistoryView(
            note: Note(title: "Site Visit", body: "Walked the north wing.")
        )
    }
    .modelContainer(
        for: [Note.self, Folder.self, NoteDrawing.self, NoteRevision.self],
        inMemory: true
    )
}
