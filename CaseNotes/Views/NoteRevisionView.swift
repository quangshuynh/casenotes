//
//  NoteRevisionView.swift
//  CaseNotes
//
//  Created by q on 8/28/26.
//

import SwiftData
import SwiftUI

/// One previous version of a note, read the same way the note itself is read.
///
/// Opening a version changes nothing. Markdown is rendered here rather than in
/// the history list because this is the one place a whole historical body is
/// worth parsing.
struct NoteRevisionView: View {
    let revision: NoteRevision

    /// The note this version would be restored into.
    let note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRestore = false

    /// The file a placement in the historical body opened in Quick Look.
    @State private var placementPreview: PreviewedAttachment?

    /// The note's current files, for the placements this version's text makes.
    @State private var inlineAttachments = InlineAttachmentContext()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text(revision.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                metadata

                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                    .padding(.vertical, Theme.Spacing.xSmall)

                revisionBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Previous Version")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore") {
                    isConfirmingRestore = true
                }
            }
        }
        .confirmationDialog(
            "Restore This Version?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Version") {
                restore()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This version becomes the current note. The version you have now is kept in version history, and any drawing stays as it is.")
        }
        .fullScreenCover(item: $placementPreview) { preview in
            QuickLookPreview(url: preview.url, filename: preview.filename) {
                placementPreview = nil
            }
            .ignoresSafeArea()
        }
        .environment(\.inlineAttachments, inlineAttachments)
        .onAppear(perform: refreshInlineAttachments)
    }

    /// Resolves this version's placements against the note's current files.
    ///
    /// Version history records authored text and never files, so a historical
    /// body is resolved against the files the note holds now. A placement whose
    /// file has since been removed says so, which is the same honest answer the
    /// note itself gives.
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

    /// When this version was written, and the event date it carried.
    ///
    /// The edit date is stated in words rather than shown as a bare timestamp,
    /// since a screen full of dates needs to say which date it means.
    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text("Edited \(revision.updatedAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let eventDate = revision.eventDate {
                Label(
                    eventDate.formatted(date: .long, time: .omitted),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    /// The version's rendered text, or a placeholder when it held none.
    @ViewBuilder
    private var revisionBody: some View {
        if revision.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("This version had no content.")
                .font(.body)
                .italic()
                .foregroundStyle(Theme.Colors.textTertiary)
        } else {
            MarkdownText(source: revision.body)
        }
    }

    /// Makes this version current and returns to the history list.
    ///
    /// The list is where the result is visible: the version that was current a
    /// moment ago appears at the top of it.
    private func restore() {
        NoteHistory.restore(revision, to: note, in: modelContext)
        dismiss()
    }
}

#Preview("Version") {
    NavigationStack {
        NoteRevisionView(
            revision: NoteRevision(
                title: "Site Visit",
                body: "Walked the north wing.\n\n- Photograph the stairwell",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                capturedAt: Date(timeIntervalSince1970: 1_700_500_000)
            ),
            note: Note(title: "Site Visit", body: "Walked the north wing twice.")
        )
    }
    .modelContainer(
        for: [Note.self, Folder.self, NoteDrawing.self, NoteRevision.self],
        inMemory: true
    )
}
