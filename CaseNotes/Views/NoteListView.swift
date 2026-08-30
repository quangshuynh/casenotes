//
//  NoteListView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

/// The contents of one scope: the folders inside it and the notes filed in it,
/// searchable and sortable.
///
/// The scope's name is carried by the navigation bar, so the screen itself
/// leads with a thin strip stating how many notes are here and how they are
/// ordered. That keeps the ordering visible instead of hidden behind an icon,
/// and leaves the rest of the screen to the contents.
///
/// Membership is direct at every depth. A folder screen shows the folders and
/// the notes filed in that folder itself, never the contents of a folder inside
/// it, so a row's location always says exactly where the thing is. All Notes
/// stays global and therefore still includes notes at any depth.
///
/// Every note is fetched and then narrowed in memory by ``NoteOrganizer``. At
/// the scale this app is built for that keeps one code path for filtering,
/// sorting, and search, and it keeps those rules testable rather than buried in
/// a predicate.
struct NoteListView: View {
    let scope: NoteScope

    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var composition: NoteComposition?
    @State private var searchText = ""
    @State private var sortOption: NoteSortOption = .updated
    @State private var folderAction: FolderAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation for changes that reorder the list, honoring Reduce Motion.
    ///
    /// Pinning moves a row to the top, which reads as a glitch when it happens
    /// instantly. It stays instant for anyone who has asked for less motion.
    private var motion: Animation? {
        reduceMotion ? nil : Theme.Motion.reorder
    }

    /// The folder being browsed, or `nil` for All Notes and Unfiled.
    private var browsedFolder: Folder? {
        scope.folder
    }

    /// The notes on screen, after scope, search, and ordering are applied.
    private var visibleNotes: [Note] {
        NoteOrganizer.organize(
            notes,
            scope: scope,
            searchText: searchText,
            sortOption: sortOption
        )
    }

    /// Whether a search term is narrowing the screen.
    ///
    /// Search covers the notes of the scope being browsed, which is the same
    /// set the screen shows without it. Subfolders are left out of a search
    /// rather than filtered, because the field searches note text and an
    /// unfiltered folder section above filtered notes would misread as results.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Organizing is filtering plus a sort over every note, and grouping is
        // one pass over every folder. Both are done once per update and handed
        // to the subviews that need them, rather than recomputed per row.
        let visible = visibleNotes
        let tree = FolderTree(folders)
        let counts = ScopeCounts(notes: notes)
        let children = browsedFolder.map(tree.children) ?? []

        return Group {
            if isSearching {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    VStack(spacing: 0) {
                        contextBar(count: visible.count)
                        contentList(children: [], notes: visible, tree: tree, counts: counts)
                    }
                }
            } else if children.isEmpty && visible.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if !visible.isEmpty {
                        contextBar(count: visible.count)
                    }

                    contentList(
                        children: children,
                        notes: visible,
                        tree: tree,
                        counts: counts
                    )
                }
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                createControl
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

    /// Creation offered for this scope.
    ///
    /// Inside a folder both a note and a folder can be started, and each lands
    /// in the folder being browsed rather than at the top level. All Notes and
    /// Unfiled have no location to create a folder in, so they keep the single
    /// note action.
    @ViewBuilder
    private var createControl: some View {
        if let folder = browsedFolder {
            Menu {
                Button {
                    beginComposingNote(in: folder)
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }

                Button {
                    folderAction = .create(parent: folder)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("New", systemImage: "plus")
            }
        } else {
            Button {
                beginComposingNote(in: browsedFolder)
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
    }

    /// The strip above the list: how much is here, and in what order.
    ///
    /// - Parameter count: How many notes the list is showing.
    /// - Returns: The context strip.
    private func contextBar(count: Int) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(count == 1 ? "1 note" : "\(count) notes")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer(minLength: Theme.Spacing.small)

            sortMenu
        }
        .padding(.horizontal, Theme.Spacing.large)
        .frame(minHeight: Theme.Layout.minimumRowHeight)
        .background(Theme.Colors.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
    }

    /// The ordering control, labelled with the ordering it is currently using.
    ///
    /// The visible capsule stays small while the tappable area keeps a full
    /// row's height, so a compact control is not a harder one to hit.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOption) {
                ForEach(NoteSortOption.allCases) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xSmall) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortOption.rawValue)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.xSmall)
            .background(Theme.Colors.surface, in: Capsule())
            .frame(minHeight: Theme.Layout.minimumRowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort Notes")
        .accessibilityValue(sortOption.rawValue)
    }

    /// Shown when a scope holds nothing at all, as opposed to no search results.
    ///
    /// A folder that holds folders is never empty, so this only appears when
    /// there is genuinely nothing here. Both creation actions are offered
    /// inside a folder, because an empty folder is exactly where a user is most
    /// likely to want either one.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(scope == .all ? "No Notes" : "Nothing Here Yet", systemImage: "note.text")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            Button("New Note") {
                beginComposingNote(in: browsedFolder)
            }
            .buttonStyle(.borderedProminent)

            if let folder = browsedFolder {
                Button("New Folder") {
                    folderAction = .create(parent: folder)
                }
            }
        }
    }

    /// Explains why a scope is empty in terms of what it collects.
    private var emptyStateDescription: String {
        switch scope {
        case .all:
            "Create your first note to get started."
        case .unfiled:
            "Notes without a folder appear here."
        case .folder:
            "Notes filed here appear below, and this folder can hold folders of its own."
        }
    }

    /// The screen's contents: the folders inside this one, then its notes.
    ///
    /// Headers appear only when both kinds of content are on screen. A folder
    /// holding nothing but notes, and every library scope, therefore reads as
    /// the same plain list of notes it always has.
    ///
    /// - Parameters:
    ///   - children: Folders filed directly in the browsed folder.
    ///   - notes: The already organized notes to show.
    ///   - tree: Folders grouped by the folder they sit in.
    ///   - counts: Note counts for every scope.
    /// - Returns: The configured list.
    private func contentList(
        children: [Folder],
        notes: [Note],
        tree: FolderTree,
        counts: ScopeCounts
    ) -> some View {
        List {
            if !children.isEmpty {
                Section {
                    ForEach(children) { child in
                        FolderLink(
                            folder: child,
                            noteCount: counts.count(for: .folder(child)),
                            childCount: tree.childCount(of: child),
                            action: $folderAction,
                            onComposeNote: { beginComposingNote(in: child) }
                        )
                    }
                } header: {
                    WorkspaceSectionHeader("Folders") {
                        Button {
                            folderAction = .create(parent: browsedFolder)
                        } label: {
                            Label("Folder", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("New Folder")
                    }
                }
            }

            if !notes.isEmpty {
                if children.isEmpty {
                    noteRows(notes, tree: tree)
                } else {
                    Section {
                        noteRows(notes, tree: tree)
                    } header: {
                        WorkspaceSectionHeader("Notes")
                    }
                }
            }
        }
        .workspaceList()
    }

    /// The note rows, with pinning, refiling, and deletion attached.
    ///
    /// - Parameters:
    ///   - visible: The already organized notes to show.
    ///   - tree: Folders grouped by the folder they sit in.
    /// - Returns: The rows.
    private func noteRows(_ visible: [Note], tree: FolderTree) -> some View {
        ForEach(visible) { note in
            NavigationLink {
                NoteDetailView(note: note)
            } label: {
                NoteRowView(note: note, showsFolder: scope == .all)
            }
            .workspaceRow()
            .swipeActions(edge: .leading) {
                Button {
                    withAnimation(motion) {
                        note.isPinned.toggle()
                    }
                } label: {
                    Label(
                        note.isPinned ? "Unpin" : "Pin",
                        systemImage: note.isPinned ? "pin.slash" : "pin"
                    )
                }
                .tint(Theme.Colors.accent)
            }
            .contextMenu {
                moveMenu(for: note, tree: tree)
            }
        }
        .onDelete(perform: deleteNotes)
    }

    /// Quick refiling without opening the editor.
    ///
    /// Destinations read in tree order and are labelled with their full path,
    /// so two folders sharing a name are told apart by where they sit rather
    /// than left ambiguous. A note can be filed at any depth, since nesting
    /// organizes folders rather than restricting where a note may live.
    ///
    /// Filing is organization rather than authorship, so moving a note here
    /// leaves its edit timestamp alone.
    ///
    /// - Parameters:
    ///   - note: The note being refiled.
    ///   - tree: Folders grouped by the folder they sit in.
    /// - Returns: The move menu.
    @ViewBuilder
    private func moveMenu(for note: Note, tree: FolderTree) -> some View {
        Menu {
            Button("Unfiled") {
                note.folder = nil
            }
            .disabled(note.folder == nil)

            ForEach(tree.destinations()) { destination in
                Button(destination.pathText) {
                    note.folder = destination.folder
                }
                .disabled(note.folder?.persistentModelID == destination.id)
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
    }

    /// Opens the editor for a new note.
    ///
    /// A note created while browsing a folder is filed in that exact folder,
    /// and one started from a subfolder's menu is filed in the subfolder rather
    /// than in the folder being browsed.
    ///
    /// - Parameter folder: The folder the note starts out filed in, or `nil` to
    ///   start it unfiled.
    private func beginComposingNote(in folder: Folder?) {
        composition = NoteComposition(in: folder)
    }

    /// Deletes notes at positions in the visible list.
    ///
    /// The offsets come from the `ForEach` over ``visibleNotes``, so they must be
    /// resolved against that same filtered and sorted array rather than against
    /// every note, or the wrong notes would be deleted while searching.
    ///
    /// - Parameter offsets: Positions within ``visibleNotes``.
    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleNotes[index])
        }
    }
}

#Preview {
    NavigationStack {
        NoteListView(scope: .all)
    }
    .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}
