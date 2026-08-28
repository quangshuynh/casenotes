//
//  NoteDrawingView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import PencilKit
import SwiftData
import SwiftUI

/// A stored drawing, rendered for reading.
///
/// The image is produced lazily when this view appears and is rebuilt only when
/// the underlying bytes change, so opening a text-only note never touches
/// PencilKit and scrolling a list never renders a sketch.
struct NoteDrawingView: View {
    let drawing: NoteDrawing

    /// What the card has to show for this drawing.
    ///
    /// Rendering can legitimately produce nothing, for stored bytes that no
    /// longer decode into strokes. That is a settled outcome rather than a
    /// pending one, so it is kept distinct from the wait: an optional image
    /// alone would leave a spinner turning over a drawing that is never coming.
    private enum RenderState {
        case rendering
        case ready(UIImage)
        case unavailable
    }

    @State private var state = RenderState.rendering

    var body: some View {
        Group {
            switch state {
            case let .ready(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .accessibilityLabel("Drawing")

            case .rendering:
                placeholder {
                    ProgressView()
                }
                .accessibilityLabel("Loading drawing")

            case .unavailable:
                placeholder {
                    Label("Drawing unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .accessibilityLabel("Drawing unavailable")
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.paper)
        .clipShape(.rect(cornerRadius: Theme.Radius.medium))
        // The card is light paper in either appearance, so everything drawn on
        // it resolves against the light palette too. Left to the system
        // appearance, a spinner or a message would be pale text on pale paper
        // for anyone reading in dark mode.
        .environment(\.colorScheme, .light)
        // Keyed on the edit time rather than the bytes: the identifier is
        // compared on every update, and a drawing is large enough that comparing
        // it would be real work. Reading `data` inside the task also keeps the
        // externally stored blob out of view updates entirely.
        .task(id: drawing.updatedAt) {
            state = render(from: drawing.data).map(RenderState.ready) ?? .unavailable
        }
    }

    /// The paper card shown while there is no image to draw.
    ///
    /// - Parameter content: What to centre on the card.
    /// - Returns: A card matching the height a rendered drawing settles at.
    private func placeholder(
        @ViewBuilder content: () -> some View
    ) -> some View {
        Rectangle()
            .fill(Theme.Colors.paper)
            .frame(height: 160)
            .overlay(content: content)
            // One element carrying the caller's label, so a spinner or an icon
            // and its caption are not announced as separate things.
            .accessibilityElement(children: .ignore)
    }

    /// Rasterizes the stored drawing at the current display scale.
    ///
    /// Rendering is pinned to the light appearance. PencilKit inverts ink for
    /// dark mode as it rasterizes, which would turn black strokes white on the
    /// light paper this drawing is shown against. Forcing the trait keeps the
    /// image identical to what was drawn on the canvas.
    ///
    /// - Parameter data: The stored drawing bytes.
    /// - Returns: The rendered image, or `nil` when the drawing is empty or the
    ///   data cannot be decoded.
    private func render(from data: Data) -> UIImage? {
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
