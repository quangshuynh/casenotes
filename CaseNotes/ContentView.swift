//
//  ContentView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

enum NoteSortOption: String, CaseIterable, Identifiable {
    case updated = "Last Updated"
    case created = "Date Created"

    var id: Self { self }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]

    @State private var isPresentingNewNote = false
    @State private var newNote = Note()
    @State private var searchText = ""
    @State private var sortOption: NoteSortOption = .updated

    private var visibleNotes: [Note] {
        let filtered: [Note]

        if searchText.isEmpty {
            filtered = notes
        } else {
            filtered = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText)
                    || note.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            switch sortOption {
            case .updated:
                return lhs.updatedAt > rhs.updatedAt
            case .created:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Create your first note to get started.")
                    )
                } else if visibleNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    noteList
                }
            }
            .background(Theme.Colors.canvas)
            .navigationTitle("Notes")
            .searchable(
                text: $searchText,
                prompt: "Search notes"
            )
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
                        newNote = Note()
                        isPresentingNewNote = true
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewNote) {
                NavigationStack {
                    NoteEditorView(note: newNote)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    isPresentingNewNote = false
                                }
                            }

                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    newNote.updatedAt = Date()
                                    modelContext.insert(newNote)
                                    isPresentingNewNote = false
                                }
                                .disabled(
                                    newNote.title.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty
                                )
                            }
                        }
                }
            }
        }
    }

    private var noteList: some View {
        List {
            ForEach(visibleNotes) { note in
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    NoteRowView(note: note)
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
            }
            .onDelete(perform: deleteNotes)
        }
        .appCanvasBackground()
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleNotes[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
