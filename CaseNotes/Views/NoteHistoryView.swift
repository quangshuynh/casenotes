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
                    .workspaceRow()
                }
            } header: {
                WorkspaceSectionHeader("Previous Versions")
            } footer: {
                Text("The note as it reads now is the current version and is not listed here.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.small)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: Theme.Spacing.large,
                            bottom: Theme.Spacing.medium,
                            trailing: Theme.Spacing.large
                        )
                    )
                    // A plain list draws its own ground behind a footer, which
                    // is black rather than the warm canvas the rest of the
                    // screen uses.
                    .listRowBackground(Theme.Colors.canvas)
            }
        }
        .workspaceList()
    }
}

/// One previous version summarized for the history list.
///
/// The layout follows a note row: the title with its date alongside, then a
/// short preview. The preview is the plain-text form rather than rendered
/// Markdown, so showing a long history costs no parsing beyond the opening of
/// each body.
private struct NoteRevisionRowView: View {
    let revision: NoteRevision

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                date
                previewText
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    title

                    Spacer(minLength: Theme.Spacing.small)

                    date
                }

                previewText
            }
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }

    /// The title this version carried.
    private var title: some View {
        Text(revision.displayTitle)
            .font(.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    /// A short plain-text preview of the version.
    @ViewBuilder
    private var previewText: some View {
        if !preview.isEmpty {
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    /// When this version was written, which is what tells two versions apart.
    private var date: some View {
        Text(formattedDate)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
            .accessibilityLabel("Edited \(spokenDate)")
    }

    /// The version's date as the row shows it.
    ///
    /// Compact, like every other browsing row, but keeping the time of day:
    /// versions of one note are often minutes rather than days apart, so a bare
    /// day would leave two of them looking identical.
    private var formattedDate: String {
        ListDateStyle.text(
            for: revision.updatedAt,
            relativeTo: .now,
            includingTime: true
        )
    }

    /// The same date spelled in full for VoiceOver.
    private var spokenDate: String {
        ListDateStyle.spokenText(for: revision.updatedAt)
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
