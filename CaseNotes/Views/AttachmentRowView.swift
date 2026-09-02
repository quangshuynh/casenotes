//
//  AttachmentRowView.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import SwiftUI

/// One attached file, summarized as a row.
///
/// The same row serves the editor and the reading screen, so a file looks the
/// same whether it is staged, saved, or being removed. It says three things:
/// the name the file arrived with, what kind of file it is, and how big it is.
/// Type and size are written out rather than left to the symbol, which is a
/// hint rather than the answer.
///
/// A file whose bytes have gone missing still draws. An attachment that cannot
/// be opened is a fact worth stating on the row, and it must never be a reason
/// the rest of the note stops rendering.
struct AttachmentRowView: View {
    let descriptor: AttachmentDescriptor

    /// Whether the file behind this row is gone.
    var isMissing = false

    /// Whether the row leads somewhere when tapped.
    var showsDisclosure = false

    /// The leading symbol column, grown with the text it sits beside.
    @ScaledMetric(relativeTo: .body) private var rowIconWidth = Theme.Layout.rowIconWidth

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: isMissing ? "exclamationmark.triangle" : descriptor.symbolName)
                .font(.body)
                .foregroundStyle(isMissing ? Theme.Colors.textTertiary : Theme.Colors.accent)
                .frame(width: rowIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text(descriptor.originalFilename)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    // One line normally, because the kind and the size are a
                    // caption under a name. At accessibility sizes it wraps
                    // instead: the same words in two lines beat half a size
                    // ending in an ellipsis.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            Spacer(minLength: Theme.Spacing.small)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(minHeight: Theme.Layout.minimumRowHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// What the second line says.
    ///
    /// A missing file states that instead of its size, because the size on
    /// record describes bytes that are no longer there.
    private var detailText: String {
        isMissing ? "\(descriptor.typeName) \u{00B7} File missing" : descriptor.detailText()
    }

    /// The whole row spoken as one phrase.
    private var accessibilityDescription: String {
        guard isMissing else {
            return descriptor.spokenDescription()
        }

        return "\(descriptor.originalFilename), \(descriptor.typeName), file missing"
    }
}

#Preview {
    List {
        AttachmentRowView(
            descriptor: AttachmentDescriptor(
                originalFilename: "mitigation.docx",
                contentTypeIdentifier: "org.openxmlformats.wordprocessingml.document",
                byteCount: 43_008
            ),
            showsDisclosure: true
        )
        .workspaceRow()

        AttachmentRowView(
            descriptor: AttachmentDescriptor(
                originalFilename: "site-plan.pdf",
                contentTypeIdentifier: "com.adobe.pdf",
                byteCount: 1_248_000
            ),
            isMissing: true,
            showsDisclosure: true
        )
        .workspaceRow()
    }
    .workspaceList()
}
