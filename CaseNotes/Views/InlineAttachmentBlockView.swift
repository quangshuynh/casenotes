//
//  InlineAttachmentBlockView.swift
//  CaseNotes
//
//  Created by q on 9/3/26.
//

import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What a note's Markdown needs in order to draw the files it places.
///
/// Passed through the environment rather than down every initializer, because
/// a placement can appear at any depth of a parsed body and the views between
/// it and the note know nothing about attachments. Both halves are supplied by
/// the screen that owns the note: what a marker refers to, and what happens
/// when the reader opens it.
///
/// The default resolves nothing and opens nothing, so a Markdown preview with
/// no note behind it draws a placement as unavailable rather than pretending.
struct InlineAttachmentContext {
    var source = InlineAttachmentSource.unavailable

    /// Shows a file, usually in Quick Look. `nil` where opening is not offered.
    var open: ((ResolvedInlineAttachment) -> Void)?
}

private struct InlineAttachmentContextKey: EnvironmentKey {
    static let defaultValue = InlineAttachmentContext()
}

extension EnvironmentValues {
    /// The note's files, for the placements its Markdown makes.
    var inlineAttachments: InlineAttachmentContext {
        get { self[InlineAttachmentContextKey.self] }
        set { self[InlineAttachmentContextKey.self] = newValue }
    }
}

/// One of the note's files, drawn where the author placed it.
///
/// Two presentations, decided by what the file is. An image is worth showing,
/// so it is drawn inline at a bounded size. Everything else is named: a PDF or
/// a Word document is a flat row that opens in Quick Look, which already reads
/// both. Nothing here renders a document format, and nothing here is a card.
///
/// A placement the note cannot resolve still draws. Markdown outlives the files
/// it names, so a body may refer to an attachment that has been deleted, and
/// the row says so rather than disappearing. The author's marker is untouched
/// either way: nothing in this view writes to a note.
struct InlineAttachmentBlockView: View {
    let id: UUID

    @Environment(\.inlineAttachments) private var context

    var body: some View {
        if let attachment = context.source.attachment(for: id) {
            resolved(attachment)
        } else {
            unavailableRow
        }
    }

    /// A placement whose attachment the note still holds.
    ///
    /// - Parameter attachment: The resolved file.
    /// - Returns: The image or the row that stands for it.
    @ViewBuilder
    private func resolved(_ attachment: ResolvedInlineAttachment) -> some View {
        let isMissing = attachment.url == nil

        Button {
            guard let open = context.open, !isMissing else {
                return
            }

            open(attachment)
        } label: {
            if attachment.isImage, let url = attachment.url {
                InlineAttachmentImageView(
                    id: attachment.id,
                    url: url,
                    descriptor: attachment.descriptor
                )
            } else {
                AttachmentRowView(
                    descriptor: attachment.descriptor,
                    isMissing: isMissing,
                    showsDisclosure: !isMissing && context.open != nil
                )
            }
        }
        // Borderless for the same reason the controls beside it are: a form
        // row routes every plain button in it to one target, and a placement
        // shares its row with the writing around it and with its own controls.
        // The label sets its own colors, so the style changes nothing visible.
        .buttonStyle(.borderless)
        .disabled(isMissing || context.open == nil)
        .accessibilityHint(isMissing || context.open == nil ? "" : "Opens a preview")
    }

    /// A placement naming an attachment the note no longer holds.
    ///
    /// It is drawn rather than skipped, and the marker behind it is left in the
    /// source. Quietly deleting an author's text to tidy the screen would be a
    /// worse trade than showing them that a reference has gone stale.
    private var unavailableRow: some View {
        InlineAttachmentNoticeRow(
            title: "Attachment unavailable",
            detail: "This file is no longer part of the note."
        )
    }
}

/// A flat row stating that a placement cannot be drawn.
///
/// The symbol is a hint and the words are the answer, so the state survives any
/// color vision and any appearance.
struct InlineAttachmentNoticeRow: View {
    let title: String
    let detail: String

    @ScaledMetric(relativeTo: .body) private var rowIconWidth = Theme.Layout.rowIconWidth

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle")
                .font(.body)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: rowIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer(minLength: Theme.Spacing.small)
        }
        .frame(minHeight: Theme.Layout.minimumRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// An image attachment shown in the note.
///
/// The file is decoded once, off the main actor, and only as large as the page
/// can use. A note holding several photographs is otherwise a note that stalls
/// while it is being typed into, since full resolution decoding of a camera
/// image costs more than every other thing a keystroke does put together.
///
/// The bounds are the block's: full width, aspect ratio preserved, and a
/// ceiling on height so a tall image does not push the rest of the note off the
/// screen. Nothing floats, nothing is resized by hand, and text never wraps
/// around it.
private struct InlineAttachmentImageView: View {
    let id: UUID
    let url: URL
    let descriptor: AttachmentDescriptor

    /// The tallest an inline image is drawn.
    ///
    /// Fixed rather than scaled with Dynamic Type: the reader's text size
    /// changes how large the words are, not how large a photograph is, and
    /// growing the picture would push the writing around it off the screen.
    private static let maximumHeight: CGFloat = 280

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maximumHeight, alignment: .leading)
                    .clipShape(.rect(cornerRadius: Theme.Radius.small))
            } else if didFail {
                AttachmentRowView(descriptor: descriptor)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Theme.Colors.surface)
                    .frame(height: Theme.Layout.minimumRowHeight * 2)
                    .frame(maxWidth: .infinity)
            }

            Text(descriptor.originalFilename)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image, \(descriptor.spokenDescription())")
        .task(id: url) {
            guard image == nil else {
                return
            }

            let loaded = await InlineAttachmentImageCache.thumbnail(for: url, id: id)

            image = loaded
            didFail = loaded == nil
        }
    }
}

/// Decodes attachment images at a bounded size and remembers the results.
///
/// Two rules, both about the typing path. Decoding happens off the main actor,
/// because a note being written to redraws on every keystroke. And a decoded
/// image is kept, because live preview divides a note again as it is typed
/// into and would otherwise decode the same photograph repeatedly. `NSCache`
/// gives the memory back on its own when the system asks for it.
enum InlineAttachmentImageCache {
    /// The largest edge an inline image is decoded to, in pixels.
    ///
    /// Comfortably more than the block it is drawn in can use at any device
    /// scale, and far less than a camera image holds.
    private static let maximumPixelSize = 1_400

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12

        return cache
    }()

    /// A decoded image for an attachment.
    ///
    /// - Parameters:
    ///   - url: Where the file is now.
    ///   - id: The attachment's identity, which is what the result is kept
    ///     under. A file moves from staging into permanent storage on save
    ///     without its bytes changing, so keying on identity rather than on the
    ///     path is what stops a save costing a second decode.
    /// - Returns: The image, or `nil` when the file does not decode.
    static func thumbnail(for url: URL, id: UUID) async -> UIImage? {
        let key = id.uuidString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let size = maximumPixelSize
        let decoded = await Task.detached(priority: .userInitiated) {
            decode(url, maximumPixelSize: size)
        }.value

        if let decoded {
            cache.setObject(decoded, forKey: key)
        }

        return decoded
    }

    /// Reads a file into an image no larger than it needs to be.
    ///
    /// Image I/O rather than `UIImage(contentsOfFile:)` because it can be asked
    /// for a size: the full bitmap is never allocated, so a photograph costs
    /// what the screen uses rather than what the camera wrote.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - maximumPixelSize: The largest edge to produce.
    /// - Returns: The image, or `nil` when the bytes are not a readable image.
    nonisolated private static func decode(
        _ url: URL,
        maximumPixelSize: Int
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: thumbnail)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
        InlineAttachmentBlockView(id: UUID())

        InlineAttachmentNoticeRow(
            title: "Attachment unavailable",
            detail: "This file is no longer part of the note."
        )
    }
    .padding()
    .background(Theme.Colors.canvas)
}
