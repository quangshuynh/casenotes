//
//  NoteEditorView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @State private var eventDateEnabled: Bool
    @State private var hasChanges = false
    
    init(note: Note) {
        self.note = note
        _eventDateEnabled  = State(
                initialValue: note.eventDate != nil
            )
    }
    

    var body: some View {
        Form {
            TextField("Title", text: $note.title)
            
            TextEditor(text: $note.body)
                .frame(minHeight: 200)
            
            Toggle("Event Date", isOn: $eventDateEnabled)
                .onChange(of: eventDateEnabled) { _, enabled in
                    if enabled {
                        note.eventDate = note.eventDate ?? Date()
                    } else {
                        note.eventDate = nil
                    }
                }
            
            if eventDateEnabled {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: {
                            note.eventDate ?? Date()
                        },
                        set: {
                            note.eventDate = $0
                        }
                    ),
                    displayedComponents: .date
                )
            }
        }
        .onChange(of: note.title) { _, _ in
            hasChanges = true
        }
        .onChange(of: note.body) { _, _ in
            hasChanges = true
        }
        .onChange(of: note.eventDate) { _, _ in
            hasChanges = true
        }
        .navigationTitle("Edit Note")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: exportText,
                    subject: Text(note.title),
                    message: Text("Exported from CaseNotes")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onDisappear {
            if hasChanges {
                note.updatedAt = Date()
            }
        }
    }
    private var exportText: String {
        let title = note.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if title.isEmpty {
            return note.body
        }

        return """
        \(title)

        \(note.body)
        """
    }
}



#Preview {
    NavigationStack {
        NoteEditorView(
            note: Note(
                title: "Meeting Notes",
                body: "Follow up on the project timeline."
            )
        )
    }
}
