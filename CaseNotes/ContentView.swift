//
//  ContentView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]

    @State private var isPresentingNewNote = false
    @State private var newNote = Note()
    @State private var searchText = ""
    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else {
            return notes
        }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText)
                || note.body.localizedCaseInsensitiveContains(searchText)
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
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            NavigationLink {
                                NoteEditorView(note: note)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.headline)

                                    Text(note.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete(perform: deleteNotes)
                    }
                }
            }
            .navigationTitle("Notes")
            .searchable (
                text: $searchText,
                prompt: "Search notes"
                )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newNote = Note()
                        isPresentingNewNote = true
                    } label: {
                        Image(systemName: "plus")
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

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredNotes[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
