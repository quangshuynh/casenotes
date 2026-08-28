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
struct NoteEditorView: View {
    /// Whether the editor is composing a new note or revising a stored one.
    ///
    /// The mode affects presentation only. Persistence is entirely the caller's
    /// responsibility.
    enum Mode {
        case create
        case edit

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
    private let onSave: (NoteDraft) -> Void

    @State private var draft: NoteDraft
    @State private var eventDateEnabled: Bool
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - draft: The starting contents. For `.edit` this is built from the note
    ///     being revised, for `.create` it is usually empty.
    ///   - mode: Whether a new note is being composed or an existing one revised.
    ///   - onSave: Receives the finished draft when the user confirms. The
    ///     caller decides how it is persisted.
    init(
        draft: NoteDraft,
        mode: Mode,
        onSave: @escaping (NoteDraft) -> Void
    ) {
        self.mode = mode
        self.originalDraft = draft
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
                        dismiss()
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
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .task {
            if mode == .create {
                focusedField = .title
            }
        }
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
            mode: .edit
        ) { _ in }
    }
}

#Preview("Create") {
    NavigationStack {
        NoteEditorView(draft: NoteDraft(), mode: .create) { _ in }
    }
}
