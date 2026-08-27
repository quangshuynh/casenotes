//
//  ContentView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

struct ContentView: View {
    @State private var notes: [Note] = [] // empty array

    @State private var isPresentingNewNote = false
    @State private var newNote = Note()

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
                        ForEach($notes) { $note in
                            NavigationLink {
                                NoteEditorView(note: $note)
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
                        .onDelete { indexSet in
                            notes.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Notes")
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
                    NoteEditorView(note: $newNote)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    isPresentingNewNote = false
                                }
                            }

                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    newNote.updatedAt = Date()
                                    notes.append(newNote)
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
}

#Preview {
    ContentView()
}
