//
//  QuickLookPreview.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import QuickLook
import SwiftUI
import UIKit

/// A file the reading screen is showing in the system preview.
///
/// A URL alone cannot drive a presentation that takes an identified item, and
/// identity here is the attachment rather than the path: two files could sit at
/// the same place over the life of a note, and the preview should be rebuilt
/// when the attachment changes rather than when the string does.
///
/// The name travels alongside the URL because the file on disk is named after
/// the attachment's identity rather than after the document, so the URL cannot
/// supply a title anyone would recognize.
struct PreviewedAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let filename: String
}

/// The file Quick Look is asked to show, titled with the name the user knows.
///
/// `NSURL` already satisfies `QLPreviewItem`, but it titles the preview with
/// the last path component, which here is a UUID. A small item type is the only
/// way to keep the stored name opaque and still show the reader
/// `site-plan.pdf`.
private final class QuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

/// One file shown in the system's own document preview.
///
/// Quick Look is the whole implementation on purpose. It already reads every
/// format the importer accepts, including Word documents, and it brings sharing,
/// printing, and opening in another app with it. Writing a viewer for any of
/// those formats would be a worse version of something the system already does
/// well, and a Word renderer is not a thing this app is going to have.
///
/// The controller is wrapped in a navigation controller so the preview keeps a
/// bar of its own with a Done item bound to the presentation, rather than
/// relying on Quick Look noticing how it was presented.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    /// The name the file arrived with, shown as the preview's title.
    let filename: String

    /// Called when the user closes the preview.
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { _ in context.coordinator.onDismiss() }
        )

        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.item = QuickLookItem(url: url, title: filename)
        context.coordinator.onDismiss = onDismiss
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(item: QuickLookItem(url: url, title: filename), onDismiss: onDismiss)
    }

    /// Supplies the single item being previewed.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: QLPreviewItem
        var onDismiss: () -> Void

        init(item: QLPreviewItem, onDismiss: @escaping () -> Void) {
            self.item = item
            self.onDismiss = onDismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            item
        }
    }
}
