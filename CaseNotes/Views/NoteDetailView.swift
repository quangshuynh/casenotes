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
///
/// The screen reads as the end of the browsing hierarchy rather than as a
/// separate design: the same warm canvas, one quiet metadata line under the
/// title, and a toolbar that keeps editing in reach while everything occasional
/// sits in one menu.
struct NoteDetailView: View {
    let note: Note

    @State private var isEditing = false
    @State private var isDrawing = false
    @State private var isShowingHistory = false

    /// The file a placement in the body opened in Quick Look.
    ///
    /// Kept here rather than beside the block that was tapped, so one preview
    /// is presented over the screen however many placements a note makes.
    @State private var placementPreview: PreviewedAttachment?

    /// The note's files, as the placements in its body resolve them.
    ///
    /// Held in state so reading a note asks the file system about each file
    /// once rather than on every update, and so the environment the rendered
    /// body reads does not change underneath it for reasons unrelated to the
    /// note.
    @State private var inlineAttachments = InlineAttachmentContext()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text(note.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                metadata

                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                    .padding(.vertical, Theme.Spacing.xSmall)

                noteBody

                if let drawing = note.drawing {
                    NoteDrawingView(drawing: drawing)
                        .padding(.top, Theme.Spacing.small)
                }

                if !note.attachments.isEmpty {
                    NoteAttachmentsView(note: note)
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
                actionsMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .navigationDestination(isPresented: $isShowingHistory) {
            NoteHistoryView(note: note)
        }
        .fullScreenCover(isPresented: $isDrawing) {
            NoteDrawingEditorView(note: note)
        }
        .fullScreenCover(item: $placementPreview) { preview in
            QuickLookPreview(url: preview.url, filename: preview.filename) {
                placementPreview = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isEditing) {
            EditNoteSheet(note: note)
        }
        .environment(\.inlineAttachments, inlineAttachments)
        .onAppear(perform: refreshInlineAttachments)
        .onChange(of: note.attachments.count, refreshInlineAttachments)
        .onChange(of: isEditing) {
            if !isEditing {
                refreshInlineAttachments()
            }
        }
    }

    /// Resolves what the body's placements refer to, and what opening one does.
    ///
    /// Opening a file is a read. Nothing here writes to the note, so a reader
    /// who taps through every placement leaves its edit timestamp, its history,
    /// and its writing exactly as they were.
    private func refreshInlineAttachments() {
        let preview = $placementPreview

        inlineAttachments = InlineAttachmentContext(
            source: InlineAttachmentSource(
                attachments: NoteAttachments.attachments(of: note)
            )
        ) { attachment in
            guard let url = attachment.url else {
                return
            }

            preview.wrappedValue = PreviewedAttachment(
                id: attachment.id,
                url: url,
                filename: attachment.descriptor.originalFilename
            )
        }
    }

    /// Where the note sits and when it was written.
    ///
    /// One quiet line under the title, carrying only what the page cannot show
    /// otherwise: the folder it is filed in, the event it is about, and when it
    /// was last edited. It becomes a stack when the type is too large for one
    /// line, rather than truncating any of it.
    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.medium) {
                metadataItems
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                metadataItems
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Colors.textTertiary)
    }

    /// The individual pieces of the metadata line.
    @ViewBuilder
    private var metadataItems: some View {
        if let folder = note.folder {
            // The one place that states where a note lives, so it names the
            // whole path rather than the innermost folder. Deep paths shorten
            // from the front, and the line stacks before anything truncates.
            Label(FolderHierarchy.pathText(of: folder), systemImage: "folder")
                .accessibilityLabel(spokenLocation(of: folder))
        }

        if let eventDate = note.eventDate {
            let formatted = eventDate.formatted(date: .long, time: .omitted)

            Label(formatted, systemImage: "calendar")
                .accessibilityLabel("Event date \(formatted)")
        }

        Text("Edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
    }

    /// Where a note is filed, spoken with commas rather than path separators.
    ///
    /// - Parameter folder: The folder the note is filed in.
    /// - Returns: A phrase naming the folder and the folders above it.
    private func spokenLocation(of folder: Folder) -> String {
        guard let location = FolderHierarchy.spokenLocation(of: folder) else {
            return "In folder \(folder.displayName)"
        }

        return "In folder \(folder.displayName), \(location)"
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

    /// Everything a reader can do to a note apart from editing it.
    ///
    /// One named menu rather than a row of symbols. Editing is frequent enough
    /// to keep its own button, while history, drawing, and the ways a note
    /// leaves the app are occasional and read better as words than as four
    /// icons competing for the same corner.
    private var actionsMenu: some View {
        Menu {
            Button {
                isShowingHistory = true
            } label: {
                Label("Version History", systemImage: "clock.arrow.circlepath")
            }

            Button {
                isDrawing = true
            } label: {
                Label(
                    note.drawing == nil ? "Add Drawing" : "Edit Drawing",
                    systemImage: "pencil.tip.crop.circle"
                )
            }

            Section {
                shareActions
            }
        } label: {
            Label("More Actions", systemImage: "ellipsis.circle")
        }
    }

    /// The ways a note can leave the app.
    ///
    /// They are kept distinct because they serve different intents: a copy is
    /// pasted into something the user is already writing and must stay clean,
    /// while a share or a file export is a standalone artifact where a quiet
    /// footer belongs. The two file exports differ in kind rather than in
    /// wrapping: Markdown hands over the source the note is stored as, and a
    /// PDF hands over the note rendered as a document for someone who is going
    /// to read or print it rather than edit it.
    @ViewBuilder
    private var shareActions: some View {
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

        ShareLink(
            item: PDFNoteFile(note: note),
            preview: SharePreview(
                NoteExport.suggestedPDFFileName(for: note),
                image: Image(systemName: "doc.richtext")
            )
        ) {
            Label("Export PDF File", systemImage: "doc.richtext")
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
///
/// Saving is two writes rather than one because they answer different rules.
/// ``NoteHistory`` keeps the version the edit replaces, which only authored
/// text can produce, and ``NoteAttachments`` reconciles the files, which moves
/// the edit timestamp without recording a version.
private struct EditNoteSheet: View {
    let note: Note

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]

    var body: some View {
        NavigationStack {
            NoteEditorView(
                draft: NoteDraft(note: note),
                mode: .edit,
                folders: folders
            ) { draft in
                // One timestamp for the whole save, so a note whose text and
                // whose files both changed does not end up with two edit times
                // a moment apart.
                let savedAt = Date()

                NoteHistory.save(draft, to: note, in: modelContext, at: savedAt)
                NoteAttachments.apply(
                    draft.attachments,
                    to: note,
                    in: modelContext,
                    at: savedAt
                )
            }
        }
    }
}
