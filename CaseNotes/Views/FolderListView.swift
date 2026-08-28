//
//  FolderListView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

/// The root screen: the places notes can be browsed from.
///
/// Folder management lives here: creating, renaming, and deleting. Deletion is
/// confirmed and states plainly that the notes are kept, because that is the one
/// place a user could reasonably fear losing writing.
///
/// Scopes are reached by pushing rather than by selection, which keeps one
/// predictable navigation model on both iPhone and iPad and means a deleted
/// folder can never be left selected behind a stale notes list.
struct FolderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var notes: [Note]

    @State private var isCreatingFolder = false
    @State private var folderBeingRenamed: Folder?
    @State private var folderPendingDeletion: Folder?
    @State private var nameDraft = ""

    var body: some View {
        List {
            librarySection
            folderSection
        }
        .appCanvasBackground()
        .navigationTitle("CaseNotes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    nameDraft = ""
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .folderNameAlert(
            "New Folder",
            confirmTitle: "Create",
            isPresented: $isCreatingFolder,
            name: $nameDraft,
            onConfirm: createFolder
        )
        .folderNameAlert(
            "Rename Folder",
            confirmTitle: "Rename",
            isPresented: presence(of: $folderBeingRenamed),
            name: $nameDraft,
            onConfirm: renameFolder
        )
        .confirmationDialog(
            "Delete Folder?",
            isPresented: presence(of: $folderPendingDeletion),
            titleVisibility: .visible,
            presenting: folderPendingDeletion
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                deleteFolder(folder)
            }

            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text(deletionMessage(for: folder))
        }
    }

    /// Scopes that always exist, independent of how notes are filed.
    private var librarySection: some View {
        Section("Library") {
            scopeLink(for: .all, systemImage: "tray.full")
            scopeLink(for: .unfiled, systemImage: "tray")
        }
    }

    /// The user's folders, each offering rename and delete.
    private var folderSection: some View {
        Section("Folders") {
            if folders.isEmpty {
                Text("No folders yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .listRowBackground(Theme.Colors.surface)
            }

            ForEach(folders) { folder in
                scopeLink(for: .folder(folder), systemImage: "folder")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            folderPendingDeletion = folder
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            beginRenaming(folder)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(Theme.Colors.accent)
                    }
                    .contextMenu {
                        Button {
                            beginRenaming(folder)
                        } label: {
                            Label("Rename Folder", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            folderPendingDeletion = folder
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
            }
        }
    }

    /// A row that pushes the notes belonging to one scope.
    ///
    /// The count is drawn in the label rather than with `badge`, which on a
    /// navigation row places the number after the disclosure chevron instead of
    /// before it.
    ///
    /// - Parameters:
    ///   - scope: The scope to browse.
    ///   - systemImage: Symbol shown alongside the scope name.
    /// - Returns: A navigation row styled for the folder list.
    private func scopeLink(for scope: NoteScope, systemImage: String) -> some View {
        NavigationLink {
            NoteListView(scope: scope)
        } label: {
            HStack {
                Label {
                    Text(scope.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.Colors.accent)
                }

                Spacer(minLength: Theme.Spacing.small)

                Text(noteCount(in: scope).formatted())
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityLabel(noteCountLabel(for: scope))
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }

    /// How many notes a scope currently holds.
    ///
    /// - Parameter scope: The scope to count.
    /// - Returns: The number of notes shown when browsing that scope.
    private func noteCount(in scope: NoteScope) -> Int {
        notes.count(where: scope.contains)
    }

    /// Spoken form of a scope's note count.
    ///
    /// - Parameter scope: The scope being described.
    /// - Returns: A phrase such as "3 notes".
    private func noteCountLabel(for scope: NoteScope) -> String {
        let count = noteCount(in: scope)
        return count == 1 ? "1 note" : "\(count) notes"
    }

    /// The typed folder name with surrounding whitespace removed.
    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A boolean binding that follows whether an optional holds a value.
    ///
    /// Alerts and dialogs are driven by `Bool`, while the thing they act on is
    /// naturally an optional. This bridges the two and clears the optional when
    /// the presentation is dismissed.
    ///
    /// - Parameter value: The optional state driving the presentation.
    /// - Returns: A binding that reads as `true` while the value is set.
    private func presence<Value>(of value: Binding<Value?>) -> Binding<Bool> {
        Binding {
            value.wrappedValue != nil
        } set: { isPresented in
            if !isPresented {
                value.wrappedValue = nil
            }
        }
    }

    /// Spells out that deleting a folder keeps its notes.
    ///
    /// - Parameter folder: The folder about to be deleted.
    /// - Returns: Copy naming how many notes will be moved to Unfiled.
    private func deletionMessage(for folder: Folder) -> String {
        let count = folder.notes.count

        switch count {
        case 0:
            return "This folder is empty."
        case 1:
            return "1 note will be kept and moved to Unfiled."
        default:
            return "\(count) notes will be kept and moved to Unfiled."
        }
    }

    /// Opens the rename alert primed with a folder's current name.
    ///
    /// - Parameter folder: The folder to rename.
    private func beginRenaming(_ folder: Folder) {
        nameDraft = folder.name
        folderBeingRenamed = folder
    }

    /// Inserts a folder using the typed name.
    private func createFolder() {
        modelContext.insert(Folder(name: trimmedNameDraft))
    }

    /// Applies the typed name to the folder being renamed, then closes the alert.
    private func renameFolder() {
        folderBeingRenamed?.name = trimmedNameDraft
        folderBeingRenamed = nil
    }

    /// Deletes a folder, leaving its notes unfiled.
    ///
    /// The relationship's nullify delete rule does the unfiling: the folder row
    /// disappears and every note it held stays in the store, reachable under
    /// Unfiled.
    ///
    /// - Parameter folder: The folder to delete.
    private func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        folderPendingDeletion = nil
    }
}

#Preview {
    NavigationStack {
        FolderListView()
    }
    .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}

private extension View {
    /// Presents an alert asking for a folder name.
    ///
    /// Creating and renaming ask exactly the same question, so they share one
    /// presentation rather than two nearly identical alert blocks.
    ///
    /// - Parameters:
    ///   - title: Alert title.
    ///   - confirmTitle: Label for the confirming button.
    ///   - isPresented: Whether the alert is showing.
    ///   - name: The name being typed.
    ///   - onConfirm: Runs when the user confirms a non-empty name.
    /// - Returns: The view with the naming alert attached.
    func folderNameAlert(
        _ title: String,
        confirmTitle: String,
        isPresented: Binding<Bool>,
        name: Binding<String>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Name", text: name)

            Button(confirmTitle, action: onConfirm)
                .disabled(
                    name.wrappedValue
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )

            Button("Cancel", role: .cancel) {}
        }
    }
}
