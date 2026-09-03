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
///
/// Placing a file inside the writing follows the rule too, and needs no rule of
/// its own: a placement is a marker in the draft's body, so it is authored text
/// that Save keeps and Cancel discards, and the file it names is the same file
/// the attachments list is holding.
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
    @State private var markdownMode = MarkdownEditingMode.default
    @State private var eventDateEnabled: Bool
    @State private var isConfirmingDiscard = false
    @State private var isImportingAttachment = false
    @State private var attachmentErrorMessage: String?

    /// Whether the file being imported is also going to be placed in the text.
    @State private var isPlacingImportedAttachment = false

    /// Whether the sheet that chooses a file to place is presented.
    @State private var isChoosingAttachmentToPlace = false

    /// Set while the picker is closing so the importer is raised once it has
    /// gone. Two presentations cannot be raised in the same event.
    @State private var isImportRequestedFromPicker = false

    /// The note's files, as the placements in the body resolve them.
    ///
    /// Held in state and rebuilt only when the list of files changes, for two
    /// reasons. It asks the file system whether each file is still there, and
    /// it is handed to the body through the environment: a value rebuilt on
    /// every update would invalidate every rendered block on every keystroke,
    /// which is the cost this editor already learned not to pay.
    @State private var inlineAttachments = InlineAttachmentContext()

    /// The file a placement opened in Quick Look.
    @State private var placementPreview: PreviewedAttachment?

    /// Where the body is being edited, so a placement lands where the caret is.
    ///
    /// A reference type held in state, like the Markdown caches: it is written
    /// on every keystroke and read only when a file is chosen, so it must not
    /// cause a redraw.
    @State private var bodyCaret = MarkdownBodyCaret()

    /// The selection in Source mode, which is the only way that field reports
    /// where the caret is.
    @State private var sourceSelection: TextSelection?

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

                bodyEditor
            } footer: {
                Text(markdownMode.footer)
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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isChoosingAttachmentToPlace = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .disabled(!markdownMode.isEditable)
                .accessibilityLabel("Insert Attachment")
                .accessibilityHint("Places one of the note's files at the cursor")
            }

            ToolbarItem(placement: .topBarTrailing) {
                markdownModePicker
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
        .sheet(
            isPresented: $isChoosingAttachmentToPlace,
            onDismiss: raiseImporterIfRequested
        ) {
            InlineAttachmentPickerView(
                attachments: draft.attachments,
                onPick: place(attachment:),
                onImport: { isImportRequestedFromPicker = true }
            )
        }
        .fullScreenCover(item: $placementPreview) { preview in
            QuickLookPreview(url: preview.url, filename: preview.filename) {
                placementPreview = nil
            }
            .ignoresSafeArea()
        }
        .environment(\.inlineAttachments, inlineAttachments)
        .onChange(of: draft.attachments) {
            refreshInlineAttachments()
        }
        .task {
            refreshInlineAttachments()

            if mode == .create {
                focusedField = .title
            }
        }
    }

    /// The note body, presented the way the chosen Markdown mode presents it.
    ///
    /// All three modes read and write the same draft string. Reading renders it
    /// through the same view the note screen uses and offers no way to type,
    /// live preview renders everything but the region under the caret, and
    /// source is the field this editor has always had. Switching between them
    /// changes what is on screen and nothing else: no text is rewritten, the
    /// draft is not touched, and nothing reaches the store until Save.
    @ViewBuilder
    private var bodyEditor: some View {
        switch markdownMode {
        case .reading:
            if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("This note has no content yet.")
                    .font(.body)
                    .italic()
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownText(source: draft.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.xSmall)
            }

        case .livePreview:
            MarkdownLivePreview(source: $draft.body, bodyCaret: bodyCaret)
                .padding(.vertical, Theme.Spacing.xSmall)

        case .source:
            TextEditor(text: $draft.body, selection: $sourceSelection)
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .body)
                .frame(minHeight: 220)
                .accessibilityLabel("Note Body")
                .onChange(of: sourceSelection) {
                    recordSourceCaret()
                }
        }
    }

    // MARK: Placements

    /// Resolves the draft's files again after the list changed.
    ///
    /// A staged file resolves to its copy in staging, so a document attached a
    /// moment ago renders in the body straight away, and its identity is
    /// already the one the saved attachment will carry.
    ///
    /// The preview is reached through the binding rather than through a
    /// captured copy of this view, so the stored action stays valid however
    /// many times the editor is re-evaluated around it.
    private func refreshInlineAttachments() {
        let preview = $placementPreview

        inlineAttachments = InlineAttachmentContext(
            source: InlineAttachmentSource(
                draftAttachments: draft.attachments,
                store: attachmentStore
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

    /// Writes a marker for one of the note's files at the cursor.
    ///
    /// The body is the only thing that changes. Nothing is copied, no record is
    /// written, and the file itself is exactly where it was, which is why this
    /// needs no more ceremony than typing the same characters would.
    ///
    /// - Parameter id: The attachment to place.
    private func place(attachment id: UUID) {
        let insertion = InlineAttachments.inserting(
            id,
            into: draft.body,
            atUTF16Offset: bodyCaret.utf16Offset ?? draft.body.utf16.count
        )

        draft.body = insertion.source
        bodyCaret.utf16Offset = insertion.caretUTF16Offset
    }

    /// Raises the file importer once the picker has finished closing.
    ///
    /// The wait for the next turn of the run loop is load bearing. Asking for
    /// the importer inside the dismissal itself does nothing at all: the sheet
    /// is still the presented view as far as the presenting controller is
    /// concerned, so the second presentation is dropped without a word. That
    /// was found by tapping the button and watching nothing happen.
    private func raiseImporterIfRequested() {
        guard isImportRequestedFromPicker else {
            return
        }

        isImportRequestedFromPicker = false
        isPlacingImportedAttachment = true

        DispatchQueue.main.async {
            isImportingAttachment = true
        }
    }

    /// Notes where the caret is in Source mode.
    ///
    /// `TextEditor` reports a selection rather than an offset, and an offset is
    /// what a placement needs, so the two are converted here. A selection that
    /// spans text is treated as its start, because an attachment is inserted
    /// rather than something the selection is replaced by.
    private func recordSourceCaret() {
        guard let sourceSelection else {
            return
        }

        switch sourceSelection.indices {
        case let .selection(range):
            bodyCaret.utf16Offset = range.lowerBound.utf16Offset(in: draft.body)

        case let .multiSelection(ranges):
            guard let first = ranges.ranges.first else {
                return
            }

            bodyCaret.utf16Offset = first.lowerBound.utf16Offset(in: draft.body)

        @unknown default:
            return
        }
    }

    /// The control that chooses how Markdown is shown.
    ///
    /// A menu rather than a segmented control: three names do not fit across a
    /// toolbar at large text sizes, and a menu states the current mode in words
    /// beside its symbol instead of leaving it to a highlighted segment. The
    /// mode is view state and is deliberately not remembered between edits,
    /// because this app has no preference store and inventing one for a display
    /// choice would be the wrong trade.
    private var markdownModePicker: some View {
        Menu {
            Picker("Markdown Mode", selection: $markdownMode) {
                ForEach(MarkdownEditingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // Written out rather than left to the symbol. A toolbar renders a
            // menu's label icon-only where it can, and the active mode would
            // then be carried by a glyph alone.
            Text(markdownMode.title)
        }
        .accessibilityLabel("Markdown Mode")
        .accessibilityValue(markdownMode.title)
        .accessibilityHint(markdownMode.summary)
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

            Button {
                isChoosingAttachmentToPlace = true
            } label: {
                Label("Insert Into Note", systemImage: "text.append")
            }
            .disabled(!markdownMode.isEditable)
        } header: {
            Text("Attachments")
        } footer: {
            Text("Files are copied into CaseNotes and saved with the note. A file can also be placed in the writing, which adds a reference to the Markdown rather than a copy of the file.")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    /// Stages the files the importer returned.
    ///
    /// Each file is handled on its own, so one document the app cannot accept
    /// does not cost the others. A cancelled picker is not a failure and is
    /// deliberately silent.
    ///
    /// A file imported in order to be placed is staged first and placed second,
    /// through the same two steps as a file that was already attached. There is
    /// one import path and one attachment list, so a placement never becomes a
    /// second way for a file to reach the store.
    ///
    /// - Parameter result: What the file importer produced.
    private func importAttachments(_ result: Result<[URL], Error>) {
        let isPlacing = isPlacingImportedAttachment
        isPlacingImportedAttachment = false

        switch result {
        case let .success(urls):
            var failures: [String] = []

            for url in urls {
                do {
                    let staged = try attachmentStore.stage(contentsOf: url)
                    draft.attachments.append(DraftAttachment(staged: staged))

                    if isPlacing {
                        place(attachment: staged.id)
                    }
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
    /// Any place the body refers to the file is deliberately left alone. The
    /// writing is the author's, and rewriting it behind them to tidy up a
    /// reference would be a worse trade than showing the reference has gone
    /// stale, which is what the body does. Cancel restores both together,
    /// because both are the draft.
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
