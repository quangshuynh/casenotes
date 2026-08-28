//
//  DrawingCanvasView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import PencilKit
import SwiftUI

/// SwiftUI wrapper around `PKCanvasView`.
///
/// PencilKit has no SwiftUI equivalent, so UIKit interop is unavoidable here.
/// The bridging is deliberately one-directional: the caller creates and owns the
/// `PKCanvasView` and reads `canvasView.drawing` when it decides to save, while
/// this view only configures the canvas and shows the system tool picker. That
/// removes the usual representable hazard of a binding and a delegate writing to
/// each other in a loop, and it means an unsaved sketch lives only in the canvas
/// until the user commits it.
struct DrawingCanvasView: UIViewRepresentable {
    let canvasView: PKCanvasView

    /// Called whenever the canvas contents change.
    ///
    /// PencilKit's serialized form is not byte-stable across a decode and
    /// re-encode, so comparing stored bytes cannot tell an untouched drawing
    /// from an edited one. The delegate answers that question directly.
    let onDrawingChanged: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        // Finger drawing is allowed alongside Apple Pencil so the feature works
        // on any device, not only where a pencil is paired.
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = UIColor(Theme.Colors.paper)
        canvasView.isOpaque = true

        // Ink keeps the color it was drawn in, so the canvas is pinned to the
        // light appearance to match the paper it is drawn on and the image shown
        // later in reading mode.
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.delegate = context.coordinator

        context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
        context.coordinator.toolPicker.addObserver(canvasView)

        // The canvas has to be in a window before it can take first responder,
        // which is what raises the tool picker.
        DispatchQueue.main.async {
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Nothing to push: the canvas owns the in-progress drawing.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    /// Holds the tool picker and reports edits.
    ///
    /// `PKToolPicker` must outlive the call that shows it, otherwise the palette
    /// disappears as soon as it is deallocated.
    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()

        private let onDrawingChanged: () -> Void

        init(onDrawingChanged: @escaping () -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        /// Forwards every canvas change, including programmatic ones, which is
        /// why the caller gates tracking until after it loads a stored drawing.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged()
        }
    }
}
