//
//  NoteDrawingView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import PencilKit
import SwiftUI

/// A stored drawing, rendered for reading.
///
/// The image is produced lazily when this view appears and is rebuilt only when
/// the underlying bytes change, so opening a text-only note never touches
/// PencilKit and scrolling a list never renders a sketch.
struct NoteDrawingView: View {
    let data: Data

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .accessibilityLabel("Drawing")
            } else {
                Rectangle()
                    .fill(Theme.Colors.paper)
                    .frame(height: 160)
                    .overlay {
                        ProgressView()
                    }
                    .accessibilityLabel("Loading drawing")
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.paper)
        .clipShape(.rect(cornerRadius: Theme.Radius.medium))
        .task(id: data) {
            image = render()
        }
    }

    /// Rasterizes the stored drawing at the current display scale.
    ///
    /// Rendering is pinned to the light appearance. PencilKit inverts ink for
    /// dark mode as it rasterizes, which would turn black strokes white on the
    /// light paper this drawing is shown against. Forcing the trait keeps the
    /// image identical to what was drawn on the canvas.
    ///
    /// - Returns: The rendered image, or `nil` when the drawing is empty or the
    ///   data cannot be decoded.
    private func render() -> UIImage? {
        let drawing = DrawingCodec.decode(data)

        guard !drawing.bounds.isEmpty else {
            return nil
        }

        // A margin keeps strokes from touching the edge of the card.
        let bounds = drawing.bounds.insetBy(
            dx: -Theme.Spacing.medium,
            dy: -Theme.Spacing.medium
        )
        let scale = UITraitCollection.current.displayScale

        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: bounds, scale: scale)
        }

        return rendered
    }
}
