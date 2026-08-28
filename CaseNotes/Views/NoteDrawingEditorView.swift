//
//  NoteDrawingEditorView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import PencilKit
import SwiftData
import SwiftUI

/// A full-screen sketching surface for one note.
///
/// Drawing is a mode of its own rather than a section inside the text editor, so
/// the tool picker and the canvas get the whole screen and the text editing
/// experience stays uncluttered.
///
/// Save semantics match the text editor: Done commits, Cancel discards, and
/// clearing the canvas then pressing Done removes the drawing from the note.
struct NoteDrawingEditorView: View {
    let note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The live canvas.
    ///
    /// Held here so this view is the single owner of the in-progress drawing,
    /// and so Clear and Done can act on it directly.
    @State private var canvasView = PKCanvasView()
    @State private var isConfirmingClear = false

    /// Whether the user has actually drawn since the canvas was loaded.
    @State private var hasEdits = false

    /// Gates edit tracking past the programmatic load of the stored drawing,
    /// which itself notifies the delegate.
    @State private var isTrackingEdits = false

    var body: some View {
        NavigationStack {
            DrawingCanvasView(canvasView: canvasView) {
                if isTrackingEdits {
                    hasEdits = true
                }
            }
                .ignoresSafeArea(edges: .bottom)
                .background(Theme.Colors.paper)
                .navigationTitle("Drawing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) {
                            isConfirmingClear = true
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            save()
                        }
                    }
                }
                .confirmationDialog(
                    "Clear Drawing?",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("Clear Drawing", role: .destructive) {
                        canvasView.drawing = PKDrawing()
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The canvas is emptied. The drawing is removed from the note when you tap Done.")
                }
        }
        // The whole screen commits to the light appearance, matching the paper
        // the drawing sits on. Without this the navigation bar keeps the dark
        // appearance and its title is unreadable over the canvas.
        .preferredColorScheme(.light)
        .task {
            if let data = note.drawing?.data {
                canvasView.drawing = DrawingCodec.decode(data)
            }

            // Enable tracking only after the load has been delivered to the
            // delegate, so opening a drawing does not count as editing it.
            DispatchQueue.main.async {
                isTrackingEdits = true
            }
        }
    }

    /// Commits the canvas to the note and closes the editor.
    ///
    /// An untouched canvas is left alone entirely, so viewing a drawing never
    /// rewrites the note or moves its edit timestamp.
    private func save() {
        if hasEdits {
            NoteDrawing.apply(canvasView.drawing, to: note, in: modelContext)
        }

        dismiss()
    }
}
