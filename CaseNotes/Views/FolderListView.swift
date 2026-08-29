//
//  FolderListView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

/// The root screen: the workspace navigator every other screen is reached from.
///
/// Three groups answer three different questions. Library holds the scopes that
/// always exist, Folders holds the ones the user made, and Recent answers what
/// was being worked on without needing a scope at all.
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
    @State private var isComposingNote = false
    @State private var composingIntoFolder: Folder?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The leading symbol column, grown with the text it sits beside.
    ///
    /// A fixed column would keep its width while the symbol inside it scaled,
    /// so at large text sizes the icon spilled over the label next to it.
    @ScaledMetric(relativeTo: .body) private var rowIconWidth = Theme.Layout.rowIconWidth

    /// How many recently edited notes the root offers as a shortcut.
    ///
    /// Short on purpose. Recent is a way back into current work, not a second
    /// notes list, and a long one would push the folders off the screen.
    private static let recentLimit = 5

    /// Animation for rows arriving and leaving, honoring Reduce Motion.
    private var motion: Animation? {
        reduceMotion ? nil : Theme.Motion.reorder
    }

    /// Whether the store holds nothing at all, as opposed to no folders.
    private var isLibraryEmpty: Bool {
        folders.isEmpty && notes.isEmpty
    }

    var body: some View {
        // Counting notes per scope is one pass over every note, done here and
        // shared with the rows. Counting inside each row would repeat that pass
        // once for the number and again for its spoken form.
        let counts = ScopeCounts(notes: notes)

        return Group {
            if isLibraryEmpty {
                emptyLibrary
            } else {
                libraryList(counts)
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("CaseNotes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                createMenu
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
        .sheet(isPresented: $isComposingNote) {
            NavigationStack {
                NoteEditorView(
                    draft: NoteDraft(folder: composingIntoFolder),
                    mode: .create,
                    folders: folders
                ) { draft in
                    draft.insertNote(into: modelContext)
                }
            }
        }
    }

    /// The navigator itself.
    ///
    /// - Parameter counts: Note counts for every scope.
    /// - Returns: The configured list.
    private func libraryList(_ counts: ScopeCounts) -> some View {
        List {
            librarySection(counts)
            folderSection(counts)
            recentSection
        }
        .workspaceList()
    }

    /// Both ways to create, kept together so neither is hunted for.
    private var createMenu: some View {
        Menu {
            Button {
                beginComposingNote(in: nil)
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }

            Button {
                beginCreatingFolder()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("New", systemImage: "plus")
        }
    }

    /// Shown when there is nothing to navigate yet.
    ///
    /// Both creation actions are offered here rather than only in the toolbar,
    /// because this is the one screen where a user has nothing else to do.
    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Notes Yet", systemImage: "tray")
        } description: {
            Text("Write a note, or make a folder to keep related notes together.")
        } actions: {
            Button("New Note") {
                beginComposingNote(in: nil)
            }
            .buttonStyle(.borderedProminent)

            Button("New Folder") {
                beginCreatingFolder()
            }
        }
    }

    /// Scopes that always exist, independent of how notes are filed.
    ///
    /// - Parameter counts: Note counts for every scope.
    /// - Returns: The library section.
    private func librarySection(_ counts: ScopeCounts) -> some View {
        Section {
            scopeLink(for: .all, systemImage: "tray.full", counts: counts)
            scopeLink(for: .unfiled, systemImage: "tray", counts: counts)
        } header: {
            WorkspaceSectionHeader("Library")
        }
    }

    /// The user's folders, each offering note creation, rename, and delete.
    ///
    /// - Parameter counts: Note counts for every scope.
    /// - Returns: The folders section.
    private func folderSection(_ counts: ScopeCounts) -> some View {
        Section {
            if folders.isEmpty {
                Text("No folders yet. Notes without one stay in Unfiled.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .workspaceRow()
            }

            ForEach(folders) { folder in
                scopeLink(for: .folder(folder), systemImage: "folder", counts: counts)
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
                            beginComposingNote(in: folder)
                        } label: {
                            Label("New Note in Folder", systemImage: "square.and.pencil")
                        }

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
        } header: {
            WorkspaceSectionHeader("Folders") {
                Button {
                    beginCreatingFolder()
                } label: {
                    Label("Folder", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("New Folder")
            }
        }
    }

    /// A way straight back into the notes most recently worked on.
    @ViewBuilder
    private var recentSection: some View {
        let recent = NoteOrganizer.recent(notes, limit: Self.recentLimit)

        if !recent.isEmpty {
            Section {
                ForEach(recent) { note in
                    NavigationLink {
                        NoteDetailView(note: note)
                    } label: {
                        RecentNoteRowView(note: note)
                    }
                    .workspaceRow()
                }
            } header: {
                WorkspaceSectionHeader("Recent")
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
    ///   - counts: Note counts for every scope.
    /// - Returns: A navigation row styled for the workspace list.
    private func scopeLink(
        for scope: NoteScope,
        systemImage: String,
        counts: ScopeCounts
    ) -> some View {
        NavigationLink {
            NoteListView(scope: scope)
        } label: {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: rowIconWidth, alignment: .leading)

                Text(scope.title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.small)

                Text(counts.count(for: scope).formatted())
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityLabel(counts.spokenCount(for: scope))
            }
        }
        .workspaceRow()
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

    /// Opens the naming alert for a new folder.
    private func beginCreatingFolder() {
        nameDraft = ""
        isCreatingFolder = true
    }

    /// Opens the editor for a new note.
    ///
    /// - Parameter folder: The folder the note starts out filed in, or `nil` to
    ///   start it unfiled.
    private func beginComposingNote(in folder: Folder?) {
        composingIntoFolder = folder
        isComposingNote = true
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
        withAnimation(motion) {
            modelContext.insert(Folder(name: trimmedNameDraft))
        }
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
        withAnimation(motion) {
            modelContext.delete(folder)
        }

        folderPendingDeletion = nil
    }
}

#Preview {
    NavigationStack {
        FolderListView()
    }
    .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}

/// A recently edited note, summarized for the root screen.
///
/// Deliberately thinner than a row in the notes list: a name and when it was
/// touched, with no preview. Recent is a shortcut back into work, and parsing
/// Markdown for it would make opening the app pay for a list nobody reads.
private struct RecentNoteRowView: View {
    let note: Note

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var rowIconWidth = Theme.Layout.rowIconWidth

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: rowIconWidth, alignment: .leading)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                // A name and a date cannot share a line at these sizes without
                // one of them being cut in half, so they stop sharing one.
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    title
                    date
                }
            } else {
                title

                Spacer(minLength: Theme.Spacing.small)

                date
            }
        }
    }

    /// The note's name.
    private var title: some View {
        Text(note.displayTitle)
            .font(.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    /// When the note was last edited.
    private var date: some View {
        Text(ListDateStyle.text(for: note.updatedAt, relativeTo: .now))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
            .accessibilityLabel(
                "Edited \(ListDateStyle.spokenText(for: note.updatedAt))"
            )
    }
}

/// Note counts for every scope shown in the folder list.
///
/// Built in one pass so a list of folders costs a single walk over the notes
/// rather than one walk per row.
struct ScopeCounts {
    private var total = 0
    private var unfiled = 0
    private var byFolder: [PersistentIdentifier: Int] = [:]

    /// - Parameter notes: Every note in the store.
    init(notes: [Note]) {
        for note in notes {
            total += 1

            if let folder = note.folder {
                byFolder[folder.persistentModelID, default: 0] += 1
            } else {
                unfiled += 1
            }
        }
    }

    /// How many notes a scope holds.
    ///
    /// - Parameter scope: The scope to count.
    /// - Returns: The number of notes shown when browsing that scope.
    func count(for scope: NoteScope) -> Int {
        switch scope {
        case .all:
            total
        case .unfiled:
            unfiled
        case let .folder(folder):
            byFolder[folder.persistentModelID] ?? 0
        }
    }

    /// Spoken form of a scope's note count.
    ///
    /// - Parameter scope: The scope being described.
    /// - Returns: A phrase such as "3 notes".
    func spokenCount(for scope: NoteScope) -> String {
        let value = count(for: scope)
        return value == 1 ? "1 note" : "\(value) notes"
    }
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
