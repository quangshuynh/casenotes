//
//  FolderMovePickerView.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import SwiftData
import SwiftUI

/// Chooses where a folder is filed.
///
/// Only destinations that keep the folder tree intact are offered: the folder
/// itself and everything inside it are left out, so a cycle cannot be picked.
/// That is a convenience rather than the safeguard, because
/// ``FolderHierarchy/move(_:to:)`` refuses an invalid move whatever the
/// interface offers.
///
/// The library root is a destination in its own right, which is how a nested
/// folder gets back to the top level.
struct FolderMovePickerView: View {
    /// The folder being filed somewhere else.
    let folder: Folder

    @Query(sort: \Folder.name) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// One indentation step per level of nesting.
    @ScaledMetric(relativeTo: .body) private var indentStep: CGFloat = 14

    /// How far a row is allowed to indent before the depth stops showing.
    ///
    /// Deep trees would otherwise squeeze a name into the last few points of
    /// the row. The path under each name carries the location anyway, so the
    /// indentation can stop without anything becoming ambiguous.
    private static let maximumIndentedDepth = 4

    var body: some View {
        NavigationStack {
            List {
                Section {
                    rootRow

                    ForEach(destinations) { destination in
                        destinationRow(destination)
                    }
                } header: {
                    WorkspaceSectionHeader("Move To")
                } footer: {
                    Text("Moving a folder takes everything inside it along and does not change any note.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .listRowBackground(Theme.Colors.canvas)
                }
            }
            .workspaceList()
            .navigationTitle(folder.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Every folder this one may be filed into, in tree order.
    private var destinations: [FolderDestination] {
        FolderTree(folders).destinations(excludingSubtreeOf: folder)
    }

    /// The top level of the library, offered as a destination like any folder.
    private var rootRow: some View {
        row(
            title: "Library",
            systemImage: "tray.full",
            location: nil,
            depth: 0,
            isCurrent: folder.parent == nil,
            spoken: "Library, top level"
        ) {
            apply(nil)
        }
    }

    /// One folder offered as a destination.
    ///
    /// - Parameter destination: The folder, its depth, and its path.
    /// - Returns: The configured row.
    private func destinationRow(_ destination: FolderDestination) -> some View {
        row(
            title: destination.name,
            systemImage: "folder",
            location: FolderHierarchy.locationText(of: destination.folder),
            depth: destination.depth,
            isCurrent: destination.folder.persistentModelID == folder.parent?.persistentModelID,
            spoken: destination.spokenDescription
        ) {
            apply(destination.folder)
        }
    }

    /// The shared shape of a destination row.
    ///
    /// Nesting is shown twice on purpose: indentation reads as a tree at a
    /// glance, and the path under the name states the same thing in words, so
    /// the hierarchy survives at text sizes where indentation has to stop.
    ///
    /// - Parameters:
    ///   - title: The destination's name.
    ///   - systemImage: Symbol for the destination.
    ///   - location: The folders above it, or `nil` at the top level.
    ///   - depth: How far to indent the row.
    ///   - isCurrent: Whether the folder is already filed here.
    ///   - spoken: The row read as one phrase.
    ///   - select: Performs the move.
    /// - Returns: The configured row.
    private func row(
        title: String,
        systemImage: String,
        location: String?,
        depth: Int,
        isCurrent: Bool,
        spoken: String,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.accent)

                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    if let location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Theme.Spacing.small)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.leading, CGFloat(min(depth, Self.maximumIndentedDepth)) * indentStep)
            .frame(minHeight: Theme.Layout.minimumRowHeight)
            .contentShape(Rectangle())
        }
        .disabled(isCurrent)
        .workspaceRow()
        .accessibilityLabel(isCurrent ? "\(spoken), current location" : spoken)
    }

    /// Files the folder in a destination and closes the picker.
    ///
    /// - Parameter destination: The new parent, or `nil` for the library root.
    private func apply(_ destination: Folder?) {
        FolderHierarchy.move(folder, to: destination)
        dismiss()
    }
}

#Preview {
    FolderMovePickerView(folder: Folder(name: "Research"))
        .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}
