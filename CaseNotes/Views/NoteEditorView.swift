//
//  NoteEditorView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// The editing surface for a note, presented modally over the reading view.
///
/// The view owns a ``NoteDraft`` rather than the persistent model, so nothing
/// reaches the store until the caller's `onSave` handler runs. Dismissal by any
/// route other than Save discards the draft.
///
/// Attached files follow the same rule. An imported document is copied into
/// staging rather than into the note's own storage, and removing one only takes
/// it out of the draft's list, so the note keeps every file it had until the
/// caller saves. Abandoning the edit deletes whatever this session staged.
struct NoteEditorView: View {
    /// Whether the editor is composing a new note or revising a stored one.
    ///
    /// The mode affects presentation only. Persistence is entirely the caller's
    /// responsibility.
    enum Mode {
        case create
        case edit

        /// Title shown while the editor is open.
        var navigationTitle: String {
            switch self {
            case .create: "New Note"
            case .edit: "Edit Note"
            }
        }
    }

    private enum Field {
        case title
        case body
    }

    private let mode: Mode
    private let originalDraft: NoteDraft
    private let folders: [Folder]
    private let attachmentStore: AttachmentStore
    private let onSave: (NoteDraft) -> Void

    @State private var draft: NoteDraft
    @State private var eventDateEnabled: Bool
    @State private var isConfirmingDiscard = false
    @State private var isImportingAttachment = false
    @State private var attachmentErrorMessage: String?
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - draft: The starting contents. For `.edit` this is built from the note
    ///     being revised, for `.create` it is usually empty.
    ///   - mode: Whether a new note is being composed or an existing one revised.
    ///   - folders: Folders offered by the filing picker. Passed in rather than
    ///     queried so the editor stays a plain view over its inputs.
    ///   - attachmentStore: Where imported files are staged. Passed in for the
    ///     same reason the folders are, so the editor has one route to the file
    ///     system and no opinion about where it points.
    ///   - onSave: Receives the finished draft when the user confirms. The
    ///     caller decides how it is persisted.
    init(
        draft: NoteDraft,
        mode: Mode,
        folders: [Folder],
        attachmentStore: AttachmentStore = .shared,
        onSave: @escaping (NoteDraft) -> Void
    ) {
        self.mode = mode
        self.originalDraft = draft
        self.folders = folders
        self.attachmentStore = attachmentStore
        self.onSave = onSave
        _draft = State(initialValue: draft)
        _eventDateEnabled = State(initialValue: draft.eventDate != nil)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .body }

                TextEditor(text: $draft.body)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .body)
                    .frame(minHeight: 220)
                    .accessibilityLabel("Note Body")
            } footer: {
                Text("Markdown is supported. Use # for headings, * for emphasis, - for lists, > for quotes, and backticks for code.")
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Toggle("Event Date", isOn: $eventDateEnabled)
                    .onChange(of: eventDateEnabled) { _, enabled in
                        draft.eventDate = enabled ? (draft.eventDate ?? Date()) : nil
                    }

                if eventDateEnabled {
                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { draft.eventDate ?? Date() },
                            set: { draft.eventDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
            } footer: {
                Text("Attach the date an event happened, separate from when the note was written.")
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Picker("Folder", selection: $draft.folder) {
                    Text("Unfiled").tag(Folder?.none)

                    ForEach(destinations) { destination in
                        Text(destination.pathText)
                            .tag(Folder?.some(destination.folder))
                            .accessibilityLabel(destination.spokenDescription)
                    }
                }
            } footer: {
                Text("A note can be filed in a folder at any depth. Filing it does not change when it was last edited.")
            }
            .listRowBackground(Theme.Colors.surface)

            attachmentsSection
        }
        .appCanvasBackground()
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasUnsavedChanges {
                        isConfirmingDiscard = true
                    } else {
                        discardEdit()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .disabled(!draft.isSavable)
            }
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                discardEdit()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        // Presented from the form rather than from the attachments section. A
        // `Section` is a grouping rather than a view that can present, and a
        // presentation attached to one is dropped as its rows scroll away.
        .fileImporter(
            isPresented: $isImportingAttachment,
            allowedContentTypes: AttachmentStore.supportedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: importAttachments
        )
        .alert(
            "Attachment Not Added",
            isPresented: Binding(
                get: { attachmentErrorMessage != nil },
                set: { if !$0 { attachmentErrorMessage = nil } }
            ),
            presenting: attachmentErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .task {
            if mode == .create {
                focusedField = .title
            }
        }
    }

    /// The files this note will be saved with.
    ///
    /// Staged and saved files are shown alike, because from here they are the
    /// same thing: what the note will hold once the edit is confirmed. Removal
    /// is the list's own delete action rather than a control on every row, which
    /// keeps a row about the file it names and keeps the gesture the one the
    /// rest of the app already uses.
    private var attachmentsSection: some View {
        Section {
            ForEach(draft.attachments) { item in
                AttachmentRowView(descriptor: item.descriptor)
            }
            .onDelete(perform: removeAttachments)

            Button {
                isImportingAttachment = true
            } label: {
                Label("Add Attachment", systemImage: "paperclip")
            }
        } header: {
            Text("Attachments")
        } footer: {
            Text("Files are copied into CaseNotes and saved with the note. They are not included in Markdown or PDF exports.")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    /// Stages the files the importer returned.
    ///
    /// Each file is handled on its own, so one document the app cannot accept
    /// does not cost the others. A cancelled picker is not a failure and is
    /// deliberately silent.
    ///
    /// - Parameter result: What the file importer produced.
    private func importAttachments(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            var failures: [String] = []

            for url in urls {
                do {
                    let staged = try attachmentStore.stage(contentsOf: url)
                    draft.attachments.append(DraftAttachment(staged: staged))
                } catch {
                    failures.append(error.localizedDescription)
                }
            }

            if !failures.isEmpty {
                attachmentErrorMessage = failures.joined(separator: "\n")
            }

        case let .failure(error):
            guard (error as? CocoaError)?.code != .userCancelled else {
                return
            }

            attachmentErrorMessage = error.localizedDescription
        }
    }

    /// Takes files out of the draft's list.
    ///
    /// A file this edit staged is deleted straight away, since nothing refers
    /// to it any more. A file the note already has is only dropped from the
    /// list: it stays on disk and stays attached until the user saves, which is
    /// what lets Cancel put it back.
    ///
    /// - Parameter offsets: Positions within the draft's attachment list.
    private func removeAttachments(at offsets: IndexSet) {
        for staged in offsets.compactMap({ draft.attachments[$0].stagedFile }) {
            attachmentStore.discard(staged)
        }

        draft.attachments.remove(atOffsets: offsets)
    }

    /// Leaves the editor without keeping anything it staged.
    ///
    /// Dismissing alone would abandon the draft but leave imported documents
    /// sitting in staging, so the two are done together wherever an edit ends
    /// without a save.
    private func discardEdit() {
        NoteAttachments.discardStaged(draft.attachments, using: attachmentStore)
        dismiss()
    }

    /// The folders offered by the filing picker, in tree order.
    ///
    /// A picker row is one line, so nesting is carried by the destination's
    /// path rather than by indentation the control would not honor. Two folders
    /// sharing a name are told apart by where they sit.
    private var destinations: [FolderDestination] {
        FolderTree(folders).destinations()
    }

    /// Whether the draft differs from the contents the editor opened with.
    ///
    /// Drives both the discard confirmation and the block on swipe-to-dismiss,
    /// so edits are never lost silently.
    private var hasUnsavedChanges: Bool {
        draft != originalDraft
    }
}

#Preview("Edit") {
    NavigationStack {
        NoteEditorView(
            draft: NoteDraft(
                title: "Meeting Notes",
                body: "Follow up on the project timeline."
            ),
            mode: .edit,
            folders: []
        ) { _ in }
    }
}

#Preview("Create") {
    NavigationStack {
        NoteEditorView(draft: NoteDraft(), mode: .create, folders: []) { _ in }
    }
}
