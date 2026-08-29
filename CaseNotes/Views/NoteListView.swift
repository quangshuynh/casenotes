//
//  NoteListView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

/// The notes belonging to one scope, searchable and sortable.
///
/// The scope's name is carried by the navigation bar, so the screen itself
/// leads with a thin strip stating how many notes are here and how they are
/// ordered. That keeps the ordering visible instead of hidden behind an icon,
/// and leaves the rest of the screen to the notes.
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

    @State private var isPresentingNewNote = false
    @State private var searchText = ""
    @State private var sortOption: NoteSortOption = .updated
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation for changes that reorder the list, honoring Reduce Motion.
    ///
    /// Pinning moves a row to the top, which reads as a glitch when it happens
    /// instantly. It stays instant for anyone who has asked for less motion.
    private var motion: Animation? {
        reduceMotion ? nil : Theme.Motion.reorder
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

    /// Whether the scope holds any notes at all, ignoring the search term.
    ///
    /// Distinguishes "this folder is empty" from "the search found nothing".
    /// Short circuits on the first match rather than building a second array.
    private var scopeHasNotes: Bool {
        notes.contains(where: scope.contains)
    }

    var body: some View {
        // Organizing is filtering plus a sort over every note, so it is done
        // once per update and handed to the subviews that need it. Reading
        // `visibleNotes` from several places would repeat that work each time.
        let visible = visibleNotes

        return Group {
            if !scopeHasNotes {
                emptyState
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                VStack(spacing: 0) {
                    contextBar(count: visible.count)
                    noteList(visible)
                }
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewNote = true
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewNote) {
            NavigationStack {
                NoteEditorView(
                    draft: NoteDraft(folder: scope.folder),
                    mode: .create,
                    folders: folders
                ) { draft in
                    draft.insertNote(into: modelContext)
                }
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

    /// Shown when a scope holds no notes at all, as opposed to no search results.
    ///
    /// The creation action is offered here because an empty scope is exactly
    /// where a user is most likely to want one.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(scope == .all ? "No Notes" : "No Notes Here", systemImage: "note.text")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            Button("New Note") {
                isPresentingNewNote = true
            }
            .buttonStyle(.borderedProminent)
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
            "Notes filed in this folder appear here."
        }
    }

    /// The list itself, with pinning, refiling, and deletion attached.
    ///
    /// - Parameter visible: The already organized notes to show.
    /// - Returns: The configured list.
    private func noteList(_ visible: [Note]) -> some View {
        List {
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
                    moveMenu(for: note)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .workspaceList()
    }

    /// Quick refiling without opening the editor.
    ///
    /// Filing is organization rather than authorship, so moving a note here
    /// leaves its edit timestamp alone.
    @ViewBuilder
    private func moveMenu(for note: Note) -> some View {
        Menu {
            Button("Unfiled") {
                note.folder = nil
            }
            .disabled(note.folder == nil)

            ForEach(folders) { folder in
                Button(folder.displayName) {
                    note.folder = folder
                }
                .disabled(note.folder?.persistentModelID == folder.persistentModelID)
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
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
