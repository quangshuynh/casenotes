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

    /// Whether to name the note's folder.
    ///
    /// Only worth showing when the list mixes folders together, which is why it
    /// is off by default.
    var showsFolder = false

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

                if note.drawing != nil {
                    Image(systemName: "scribble")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityLabel("Contains a drawing")
                }
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: Theme.Spacing.small) {
                metadata

                if showsFolder, let folder = note.folder {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Image(systemName: "folder")
                        Text(folder.displayName)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("In folder \(folder.displayName)")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }

    /// The event date when the note has one, otherwise the last edit date.
    ///
    /// Only one date is shown so the row keeps a single quiet metadata line.
    /// A plain `HStack` is used rather than a `Label` because `List` reserves a
    /// shared icon column for labels, which would leave a gap here and pull the
    /// row separator out of alignment with its neighbours.
    @ViewBuilder
    private var metadata: some View {
        if let eventDate = note.eventDate {
            let formatted = eventDate.formatted(date: .abbreviated, time: .omitted)

            HStack(spacing: Theme.Spacing.xSmall) {
                Image(systemName: "calendar")
                Text(formatted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Event date \(formatted)")
        } else {
            Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    /// The title to display, falling back to a placeholder for untitled notes.
    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    /// A single-line preview of the note body.
    ///
    /// Markdown syntax is stripped so a heading or a bulleted list reads as
    /// prose in the list rather than as raw source.
    private var preview: String {
        MarkdownDocument.plainPreview(of: note.body)
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
