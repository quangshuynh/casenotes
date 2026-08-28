//
//  NoteDetailView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// The reading view for a single note.
///
/// Opening a note is a read-only act: nothing here mutates the model, so a note
/// can be browsed without touching its edit timestamp. Editing happens in a
/// sheet raised by the Edit button.
struct NoteDetailView: View {
    let note: Note

    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text(displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let eventDate = note.eventDate {
                    Label(
                        eventDate.formatted(date: .long, time: .omitted),
                        systemImage: "calendar"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                }

                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                    .padding(.vertical, Theme.Spacing.xSmall)

                noteBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
        }
        .background(Theme.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: exportText,
                    subject: Text(displayTitle),
                    message: Text("Exported from CaseNotes")
                ) {
                    Label("Share Note", systemImage: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                NoteEditorView(draft: NoteDraft(note: note), mode: .edit) { draft in
                    draft.apply(to: note)
                }
            }
        }
    }

    /// The rendered note text, or a quiet placeholder when the note is still empty.
    ///
    /// Bodies are stored as Markdown source and rendered only for reading, so
    /// the text the user typed is always what is persisted and shared.
    @ViewBuilder
    private var noteBody: some View {
        if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("This note has no content yet.")
                .font(.body)
                .italic()
                .foregroundStyle(Theme.Colors.textTertiary)
        } else {
            MarkdownText(source: note.body)
        }
    }

    /// The title to display, falling back to a placeholder for untitled notes.
    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    /// Plain-text representation used by the share sheet.
    private var exportText: String {
        let title = displayTitle

        guard !note.body.isEmpty else {
            return title
        }

        return """
        \(title)

        \(note.body)
        """
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(
            note: Note(
                title: "Site Visit",
                body: "Walked the north wing.\n\nPhotograph the stairwell next time.",
                eventDate: Date(timeIntervalSince1970: 1_700_086_400)
            )
        )
    }
}
