//
//  NoteDetailView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI
import UIKit

/// The reading view for a single note.
///
/// Opening a note is a read-only act: nothing here mutates the model, so a note
/// can be browsed without touching its edit timestamp. Editing happens in a
/// sheet raised by the Edit button.
struct NoteDetailView: View {
    let note: Note

    @State private var isEditing = false
    @State private var isDrawing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text(note.displayTitle)
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

                if let drawing = note.drawing {
                    NoteDrawingView(drawing: drawing)
                        .padding(.top, Theme.Spacing.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
        }
        .background(Theme.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                shareMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isDrawing = true
                } label: {
                    Label(
                        note.drawing == nil ? "Add Drawing" : "Edit Drawing",
                        systemImage: "pencil.tip.crop.circle"
                    )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .fullScreenCover(isPresented: $isDrawing) {
            NoteDrawingEditorView(note: note)
        }
        .sheet(isPresented: $isEditing) {
            EditNoteSheet(note: note)
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

    /// The three ways a note can leave the app.
    ///
    /// They are kept distinct because they serve different intents: a copy is
    /// pasted into something the user is already writing and must stay clean,
    /// while a share or a file export is a standalone artifact where a quiet
    /// footer belongs.
    private var shareMenu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = NoteExport.markdown(
                    for: note,
                    includingAttribution: false
                )
            } label: {
                Label("Copy Note", systemImage: "doc.on.doc")
            }

            ShareLink(
                item: NoteExport.markdown(for: note, includingAttribution: true),
                subject: Text(note.displayTitle),
                message: Text("A note from CaseNotes")
            ) {
                Label("Share Note", systemImage: "square.and.arrow.up")
            }

            ShareLink(
                item: MarkdownNoteFile(note: note),
                preview: SharePreview(
                    NoteExport.suggestedFileName(for: note),
                    image: Image(systemName: "doc.text")
                )
            ) {
                Label("Export Markdown File", systemImage: "arrow.down.document")
            }
        } label: {
            Label("Share and Export", systemImage: "square.and.arrow.up")
        }
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

/// Hosts the editor and supplies the folders it offers.
///
/// The folder query lives here rather than in the reading view, so reading a
/// note neither fetches folders nor re-renders when they change. It exists only
/// while the sheet is presented.
private struct EditNoteSheet: View {
    let note: Note

    @Query(sort: \Folder.name) private var folders: [Folder]

    var body: some View {
        NavigationStack {
            NoteEditorView(
                draft: NoteDraft(note: note),
                mode: .edit,
                folders: folders
            ) { draft in
                draft.apply(to: note)
            }
        }
    }
}
