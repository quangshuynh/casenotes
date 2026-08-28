//
//  NoteRowView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// A single note summarized for the notes list.
///
/// The row leads with the title, follows with a short preview of the body, and
/// closes with one low-emphasis metadata line so the note itself stays the
/// visual focus.
struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack(spacing: Theme.Spacing.small) {
                Text(displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityLabel("Pinned")
                }
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            metadata
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }

    /// The event date when the note has one, otherwise the last edit date.
    ///
    /// Only one date is shown so the row keeps a single quiet metadata line.
    @ViewBuilder
    private var metadata: some View {
        if let eventDate = note.eventDate {
            Label(
                eventDate.formatted(date: .abbreviated, time: .omitted),
                systemImage: "calendar"
            )
        } else {
            Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    /// The title to display, falling back to a placeholder for untitled notes.
    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    /// A single-paragraph preview of the note body with leading whitespace removed.
    private var preview: String {
        note.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    List {
        NoteRowView(
            note: Note(
                title: "Site Visit",
                body: "Walked the north wing. Photograph the stairwell next time.",
                isPinned: true
            )
        )
        NoteRowView(
            note: Note(
                title: "Follow Up",
                body: "Confirm the revised timeline.",
                eventDate: Date(timeIntervalSince1970: 1_700_086_400)
            )
        )
    }
    .listRowBackground(Theme.Colors.surface)
}
