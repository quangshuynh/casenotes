//
//  FolderRowView.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import SwiftUI

/// A folder summarized as a row in a browsing list.
///
/// The row says three things: what the folder is called, whether it holds
/// folders of its own, and how many notes are filed directly in it. Nesting is
/// carried by navigating into the folder rather than by indenting the row, so a
/// row on the library screen and a row inside a folder look and behave alike.
///
/// Counts are passed in rather than read from the relationship, because a list
/// of folders would otherwise fault a separate array for every row it draws.
struct FolderRowView: View {
    let folder: Folder

    /// Notes filed directly in this folder, not counting deeper ones.
    let noteCount: Int

    /// Folders filed directly in this folder.
    let childCount: Int

    /// The leading symbol column, grown with the text it sits beside.
    @ScaledMetric(relativeTo: .body) private var rowIconWidth = Theme.Layout.rowIconWidth

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: childCount > 0 ? "folder.fill" : "folder")
                .font(.body)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: rowIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text(folder.displayName)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                if childCount > 0 {
                    Text(childCountText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.small)

            Text(noteCount.formatted())
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// How many folders sit inside this one, written for the row.
    private var childCountText: String {
        childCount == 1 ? "1 folder" : "\(childCount) folders"
    }

    /// The whole row spoken as one phrase.
    ///
    /// The counts are said as what they count, so a row never reads as a name
    /// followed by a bare number, and containing folders is stated rather than
    /// left to a filled symbol.
    private var accessibilityDescription: String {
        let notes = noteCount == 1 ? "1 note" : "\(noteCount) notes"

        guard childCount > 0 else {
            return "\(folder.displayName), \(notes)"
        }

        return "\(folder.displayName), \(childCountText), \(notes)"
    }
}

#Preview {
    List {
        FolderRowView(
            folder: Folder(name: "Work"),
            noteCount: 8,
            childCount: 2
        )
        .workspaceRow()

        FolderRowView(
            folder: Folder(name: "Journal"),
            noteCount: 3,
            childCount: 0
        )
        .workspaceRow()
    }
    .workspaceList()
}
