//
//  WorkspaceSectionHeader.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import SwiftUI

/// The label that opens a group of rows in a workspace list.
///
/// Headers are deliberately quiet: small, tertiary, and set in capitals so they
/// read as structure rather than as content. Grouping is carried by the header
/// and the space above it rather than by a card around the rows, which is what
/// keeps the browsing screens dense.
///
/// A header can also carry one action, which is how creating a folder stays
/// next to the folders instead of only in the toolbar.
struct WorkspaceSectionHeader<Action: View>: View {
    private let title: String
    private let action: Action

    /// - Parameters:
    ///   - title: The group name, written normally. It is capitalized for
    ///     display only, so it stays readable when spoken.
    ///   - action: A control shown at the trailing edge of the header.
    init(_ title: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            action
                .font(.caption.weight(.semibold))
                .textCase(nil)
        }
        .padding(.top, Theme.Spacing.medium)
        .padding(.bottom, Theme.Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: Theme.Spacing.large,
                bottom: 0,
                trailing: Theme.Spacing.large
            )
        )
        .listRowBackground(Theme.Colors.canvas)
    }
}

extension WorkspaceSectionHeader where Action == EmptyView {
    /// A header with no trailing action.
    ///
    /// - Parameter title: The group name.
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

#Preview {
    List {
        Section {
            Text("All Notes")
                .workspaceRow()
        } header: {
            WorkspaceSectionHeader("Library")
        }

        Section {
            Text("Site Visits")
                .workspaceRow()
        } header: {
            WorkspaceSectionHeader("Folders") {
                Button("New Folder") {}
            }
        }
    }
    .workspaceList()
}
