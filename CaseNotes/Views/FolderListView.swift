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
/// always exist, Folders holds the top level of the ones the user made, and
/// Recent answers what was being worked on without needing a scope at all.
///
/// Only root folders are listed here. A folder holding folders of its own is
/// browsed by opening it, which is what keeps the phone screen a navigator
/// rather than an expanded tree, and what makes the same row vocabulary work at
/// every depth.
///
/// Folder management lives here for the top level and inside each folder for
/// its children, sharing one set of flows through ``FolderAction``. Deletion is
/// confirmed and states plainly that the notes and the subfolders are kept,
/// because that is the one place a user could reasonably fear losing something.
///
/// Scopes are reached by pushing rather than by selection, which keeps one
/// predictable navigation model on both iPhone and iPad and means a deleted
/// folder can never be left selected behind a stale notes list.
struct FolderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var notes: [Note]

    @State private var folderAction: FolderAction?
    @State private var composition: NoteComposition?

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

    /// Whether the store holds nothing at all, as opposed to no folders.
    private var isLibraryEmpty: Bool {
        folders.isEmpty && notes.isEmpty
    }

    var body: some View {
        // Counting notes per scope is one pass over every note, and grouping
        // folders by their parent is one pass over every folder. Both are done
        // here and shared with the rows, so a row costs no query of its own.
        let counts = ScopeCounts(notes: notes)
        let tree = FolderTree(folders)

        return Group {
            if isLibraryEmpty {
                emptyLibrary
            } else {
                libraryList(counts: counts, tree: tree)
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("CaseNotes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                createMenu
            }
        }
        .folderActions($folderAction)
        .sheet(item: $composition) { composition in
            NavigationStack {
                NoteEditorView(
                    draft: NoteDraft(folder: composition.folder),
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
    /// - Parameters:
    ///   - counts: Note counts for every scope.
    ///   - tree: Folders grouped by the folder they sit in.
    /// - Returns: The configured list.
    private func libraryList(counts: ScopeCounts, tree: FolderTree) -> some View {
        List {
            librarySection(counts)
            folderSection(counts: counts, tree: tree)
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
                folderAction = .create(parent: nil)
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
                folderAction = .create(parent: nil)
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

    /// The top level of the user's folders, each offering note creation,
    /// rename, move, and delete.
    ///
    /// - Parameters:
    ///   - counts: Note counts for every scope.
    ///   - tree: Folders grouped by the folder they sit in.
    /// - Returns: The folders section.
    private func folderSection(counts: ScopeCounts, tree: FolderTree) -> some View {
        Section {
            if tree.roots.isEmpty {
                Text("No folders yet. Notes without one stay in Unfiled.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .workspaceRow()
            }

            ForEach(tree.roots) { folder in
                FolderLink(
                    folder: folder,
                    noteCount: counts.count(for: .folder(folder)),
                    childCount: tree.childCount(of: folder),
                    action: $folderAction,
                    onComposeNote: { beginComposingNote(in: folder) }
                )
            }
        } header: {
            WorkspaceSectionHeader("Folders") {
                Button {
                    folderAction = .create(parent: nil)
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

    /// Opens the editor for a new note.
    ///
    /// - Parameter folder: The folder the note starts out filed in, or `nil` to
    ///   start it unfiled.
    private func beginComposingNote(in folder: Folder?) {
        composition = NoteComposition(in: folder)
    }
}

#Preview {
    NavigationStack {
        FolderListView()
    }
    .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}

/// A folder row that opens the folder, with the actions it offers attached.
///
/// The row is identical on the library screen and inside a folder, so both
/// screens push the same destination and offer the same menu at every depth.
struct FolderLink: View {
    let folder: Folder
    let noteCount: Int
    let childCount: Int

    /// The screen's folder flow, set by this row's actions.
    @Binding var action: FolderAction?

    /// Starts a note already filed in this folder.
    let onComposeNote: () -> Void

    var body: some View {
        NavigationLink {
            NoteListView(scope: .folder(folder))
        } label: {
            FolderRowView(
                folder: folder,
                noteCount: noteCount,
                childCount: childCount
            )
        }
        .workspaceRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                action = .delete(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                action = .rename(folder)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Theme.Colors.accent)
        }
        .contextMenu {
            Button(action: onComposeNote) {
                Label("New Note in Folder", systemImage: "square.and.pencil")
            }

            Button {
                action = .create(parent: folder)
            } label: {
                Label("New Folder Inside", systemImage: "folder.badge.plus")
            }

            Button {
                action = .rename(folder)
            } label: {
                Label("Rename Folder", systemImage: "pencil")
            }

            Button {
                action = .move(folder)
            } label: {
                Label("Move Folder", systemImage: "folder.badge.gearshape")
            }

            Button(role: .destructive) {
                action = .delete(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
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
/// rather than one walk per row. Folder counts are direct membership only: a
/// note filed in a subfolder is counted there and nowhere else, which is what
/// makes the number on a row match what opening it shows.
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
