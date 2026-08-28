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

    private var visibleNotes: [Note] {
        NoteOrganizer.organize(
            notes,
            scope: scope,
            searchText: searchText,
            sortOption: sortOption
        )
    }

    /// Notes in this scope before the search term is applied.
    ///
    /// Distinguishes "this folder is empty" from "the search found nothing".
    private var scopedNotes: [Note] {
        notes.filter(scope.contains)
    }

    var body: some View {
        Group {
            if scopedNotes.isEmpty {
                emptyState
            } else if visibleNotes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                noteList
            }
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(NoteSortOption.allCases) { option in
                            Text(option.rawValue)
                                .tag(option)
                        }
                    }
                } label: {
                    Label("Sort Notes", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewNote = true
                } label: {
                    Label("New Note", systemImage: "plus")
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
                    createNote(from: draft)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            scope.title == "All Notes" ? "No Notes" : "No Notes Here",
            systemImage: "note.text",
            description: Text(emptyStateDescription)
        )
    }

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

    private var noteList: some View {
        List {
            ForEach(visibleNotes) { note in
                NavigationLink {
                    NoteDetailView(note: note)
                } label: {
                    NoteRowView(note: note, showsFolder: scope == .all)
                }
                .listRowBackground(Theme.Colors.surface)
                .swipeActions(edge: .leading) {
                    Button {
                        note.isPinned.toggle()
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
        .appCanvasBackground()
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

    /// Inserts a note built from a finished draft.
    ///
    /// The note is created here rather than in the editor so an abandoned
    /// composition never reaches the model context.
    ///
    /// - Parameter draft: The contents confirmed by the user.
    private func createNote(from draft: NoteDraft) {
        let note = Note()
        draft.apply(to: note)
        modelContext.insert(note)
    }

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
