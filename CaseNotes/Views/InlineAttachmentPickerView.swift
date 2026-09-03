//
//  InlineAttachmentPickerView.swift
//  CaseNotes
//
//  Created by q on 9/3/26.
//

import SwiftUI

/// Chooses which of a note's files to place at the cursor.
///
/// The note's own files come first and importing is the second option, because
/// placing a document twice, or placing one that was attached earlier, is the
/// ordinary case. Offering the picker first is also what keeps one attachment
/// pipeline: a file chosen here is a file the note already has, and a new file
/// is staged by the same importer the attachments list uses rather than by a
/// second route into the store.
///
/// The sheet decides nothing. It reports which file was chosen, or that a new
/// one should be imported, and the editor does the rest.
struct InlineAttachmentPickerView: View {
    /// The files the edit currently holds, saved and staged alike.
    let attachments: [DraftAttachment]

    /// Called with the attachment to place.
    let onPick: (UUID) -> Void

    /// Called when the reader wants to attach a file that is not on the note
    /// yet.
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if attachments.isEmpty {
                        Text("This note has no files yet. Add one to place it in the text.")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(minHeight: Theme.Layout.minimumRowHeight)
                            .workspaceRow()
                    } else {
                        ForEach(attachments) { item in
                            Button {
                                onPick(item.id)
                                dismiss()
                            } label: {
                                AttachmentRowView(descriptor: item.descriptor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Places this file at the cursor")
                            .workspaceRow()
                        }
                    }
                } header: {
                    WorkspaceSectionHeader("Attached Files")
                }

                Section {
                    Button {
                        onImport()
                        dismiss()
                    } label: {
                        Label("Add File", systemImage: "paperclip")
                            .frame(minHeight: Theme.Layout.minimumRowHeight)
                    }
                    .accessibilityHint("Attaches a file to the note and places it at the cursor")
                    .workspaceRow()
                }
            }
            .workspaceList()
            .navigationTitle("Insert Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    InlineAttachmentPickerView(
        attachments: [],
        onPick: { _ in },
        onImport: {}
    )
}
