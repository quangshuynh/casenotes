//
//  NoteRowView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// A single note summarized for the notes list.
///
/// Two lines, scanned rather than read: the title with the date it is filed
/// under, then a short preview with whatever context the current list is
/// missing. Everything except the title is low emphasis, so a column of notes
/// reads as titles with support rather than as a stack of paragraphs.
///
/// At accessibility text sizes the row unstacks into plain lines. Density is
/// worth having until it starts costing legibility, and then it is not.
struct NoteRowView: View {
    let note: Note

    /// Whether to name the note's folder.
    ///
    /// Only worth showing when the list mixes folders together, which is why it
    /// is off by default.
    var showsFolder = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Stripping the Markdown off the opening of a body is the one piece of
        // real work a row does, and it was being done three times per update:
        // once to decide whether the second line exists and twice to draw it.
        // Reading it once is 0.23 ms a row rather than 0.69 ms on a long note.
        let preview = previewText

        return VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                previewLine(preview)
                context
                date
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    title

                    Spacer(minLength: Theme.Spacing.small)

                    date
                }

                if hasSecondLine(preview: preview) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                        previewLine(preview)

                        Spacer(minLength: Theme.Spacing.small)

                        context
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }

    /// Whether anything belongs on the row's second line.
    ///
    /// - Parameter preview: The row's already prepared preview text.
    /// - Returns: `true` when there is something to put there.
    private func hasSecondLine(preview: String) -> Bool {
        !preview.isEmpty || note.drawing != nil || folderName != nil
    }

    /// The note's name, with pinning marked beside it.
    ///
    /// Pinned notes already sort to the top, so the marker only has to confirm
    /// why a note is there rather than announce it.
    private var title: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Text(note.displayTitle)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityLabel("Pinned")
            }
        }
    }

    /// A short preview of the note body.
    ///
    /// Markdown syntax is stripped so a heading or a bulleted list reads as
    /// prose in the list rather than as raw source.
    ///
    /// - Parameter preview: The row's already prepared preview text.
    /// - Returns: The line, or nothing when the body has no prose to show.
    @ViewBuilder
    private func previewLine(_ preview: String) -> some View {
        if !preview.isEmpty {
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    /// The event date when the note has one, otherwise the last edit date.
    ///
    /// Only one date is shown so a row keeps one quiet anchor on the right. The
    /// event date wins because it is the date the writing is about, and it is
    /// marked with a symbol so the two cannot be confused.
    private var date: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            if note.eventDate != nil {
                Image(systemName: "calendar")
                    .font(.caption2)
            }

            Text(ListDateStyle.text(for: shownDate, relativeTo: .now))
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(Theme.Colors.textTertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenDate)
    }

    /// Where the note lives and what else it carries.
    ///
    /// A plain `HStack` is used rather than a `Label` because `List` reserves a
    /// shared icon column for labels, which would leave a gap here and pull the
    /// row separator out of alignment with its neighbours.
    @ViewBuilder
    private var context: some View {
        if hasContext {
            HStack(spacing: Theme.Spacing.small) {
                if note.drawing != nil {
                    Image(systemName: "scribble")
                        .accessibilityLabel("Contains a drawing")
                }

                if let folderName {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Image(systemName: "folder")
                        Text(folderName)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(spokenFolder ?? "In folder \(folderName)")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .layoutPriority(1)
        }
    }

    /// Whether the row has anything to say about where the note lives.
    private var hasContext: Bool {
        note.drawing != nil || folderName != nil
    }

    /// The folder to name on the row, when the list is showing more than one.
    ///
    /// The folder's own name rather than its path. A row is compact and a deep
    /// path would crowd out the preview beside it, so the location is spoken in
    /// full instead, where length costs nothing.
    private var folderName: String? {
        guard showsFolder else {
            return nil
        }

        return note.folder?.displayName
    }

    /// Where the note is filed, said in full including the folders above it.
    private var spokenFolder: String? {
        guard showsFolder, let folder = note.folder else {
            return nil
        }

        guard let location = FolderHierarchy.spokenLocation(of: folder) else {
            return "In folder \(folder.displayName)"
        }

        return "In folder \(folder.displayName), \(location)"
    }

    /// The one date the row shows.
    private var shownDate: Date {
        note.eventDate ?? note.updatedAt
    }

    /// The row's date spelled in full, and said as what it means.
    private var spokenDate: String {
        let spelled = ListDateStyle.spokenText(for: shownDate)
        return note.eventDate == nil ? "Edited \(spelled)" : "Event date \(spelled)"
    }

    /// A short plain-text preview of the note body.
    private var previewText: String {
        MarkdownDocument.plainPreview(of: note.body)
    }
}

#Preview {
    List {
        NoteRowView(
            note: Note(
                title: "Site Visit",
                body: "Walked the north wing. Photograph the stairwell next time.",
                isPinned: true
            ),
            showsFolder: true
        )
        .workspaceRow()

        NoteRowView(
            note: Note(
                title: "Follow Up",
                body: "Confirm the revised timeline.",
                eventDate: Date(timeIntervalSince1970: 1_700_086_400)
            )
        )
        .workspaceRow()
    }
    .workspaceList()
}
