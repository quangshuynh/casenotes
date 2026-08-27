//
//  NoteEditorView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

struct NoteEditorView: View {
    @Binding var note: Note

    var body: some View {
        Form {
            TextField("Title", text: $note.title)

            TextEditor(text: $note.body)
                .frame(minHeight: 200)
        }
        .navigationTitle("Edit Note")
        .onDisappear {
            note.updatedAt = Date()
        }
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(
            note: .constant(
                Note(
                    title: "Meeting Notes",
                    body: "Follow up on the project timeline."
                )
            )
        )
    }
}
