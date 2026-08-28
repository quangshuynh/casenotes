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
            Section("Library") {
                scopeLink(for: .all, systemImage: "tray.full")
                scopeLink(for: .unfiled, systemImage: "tray")
            }

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
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $nameDraft)

            Button("Create") {
                createFolder()
            }
            .disabled(trimmedNameDraft.isEmpty)

            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Rename Folder",
            isPresented: Binding(
                get: { folderBeingRenamed != nil },
                set: { presented in
                    if !presented {
                        folderBeingRenamed = nil
                    }
                }
            )
        ) {
            TextField("Name", text: $nameDraft)

            Button("Rename") {
                renameFolder()
            }
            .disabled(trimmedNameDraft.isEmpty)

            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { presented in
                    if !presented {
                        folderPendingDeletion = nil
                    }
                }
            ),
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

    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func beginRenaming(_ folder: Folder) {
        nameDraft = folder.name
        folderBeingRenamed = folder
    }

    private func createFolder() {
        modelContext.insert(Folder(name: trimmedNameDraft))
    }

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
