//
//  NoteAttachmentsView.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import SwiftUI

/// The files kept with a note, shown for reading.
///
/// It sits after the writing and the drawing because that is what it is: a
/// short appendix to the note rather than part of it. Rows are flat and told
/// apart by hairlines, matching the browsing screens rather than introducing a
/// card the reading view does not otherwise have.
///
/// Opening a file is a read, so nothing here touches the model. A preview
/// leaves the note's edit timestamp, its history, and its writing exactly as
/// they were.
struct NoteAttachmentsView: View {
    let note: Note

    private let store: AttachmentStore

    @State private var preview: PreviewedAttachment?

    /// - Parameters:
    ///   - note: The note whose files are being listed.
    ///   - store: The store that owns the files. Injected so the view has one
    ///     way to reach the file system.
    init(note: Note, store: AttachmentStore = .shared) {
        self.note = note
        self.store = store
    }

    var body: some View {
        // Ordered once and asked about once. Existence is a file system call,
        // so it is answered per attachment rather than per row redraw.
        let attachments = NoteAttachments.attachments(of: note)

        VStack(alignment: .leading, spacing: 0) {
            Text("Attachments")
                .workspaceHeaderText()
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Spacing.xSmall)

            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: 1)
                }

                row(for: attachment)
            }
        }
        .fullScreenCover(item: $preview) { preview in
            QuickLookPreview(url: preview.url, filename: preview.filename) {
                self.preview = nil
            }
            .ignoresSafeArea()
        }
    }

    /// One attachment, tappable when its file is still there.
    ///
    /// - Parameter attachment: The attachment to draw.
    /// - Returns: The row.
    @ViewBuilder
    private func row(for attachment: NoteAttachment) -> some View {
        let url = store.url(forStoredFilename: attachment.storedFilename)
        let isMissing = url.map { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? true

        Button {
            if let url {
                preview = PreviewedAttachment(
                    id: attachment.id,
                    url: url,
                    filename: attachment.originalFilename
                )
            }
        } label: {
            AttachmentRowView(
                descriptor: attachment.descriptor,
                isMissing: isMissing,
                showsDisclosure: !isMissing
            )
        }
        .buttonStyle(.plain)
        .disabled(isMissing)
        .accessibilityHint(isMissing ? "" : "Opens a preview")
    }
}

#Preview {
    NoteAttachmentsView(note: Note(title: "Site Visit"))
        .padding()
        .background(Theme.Colors.canvas)
}
