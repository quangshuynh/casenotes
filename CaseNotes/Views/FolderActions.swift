//
//  FolderActions.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import SwiftData
import SwiftUI

/// A folder flow a browsing screen is currently presenting.
///
/// Folder rows appear on the library screen and inside every folder, and both
/// offer the same four things. Holding the flow as one value means a screen
/// keeps a single piece of state and the presentations live in one place rather
/// than being written out again per screen.
enum FolderAction: Hashable, Identifiable {
    /// Name a new folder, filed inside `parent` or at the library root.
    case create(parent: Folder?)
    case rename(Folder)
    case move(Folder)
    case delete(Folder)

    var id: Self { self }

    /// The folder being acted on, or `nil` while creating one.
    var folder: Folder? {
        switch self {
        case .create: nil
        case let .rename(folder), let .move(folder), let .delete(folder): folder
        }
    }
}

extension View {
    /// Attaches the naming, moving, and deletion flows a folder row offers.
    ///
    /// The screen owns the state and its rows set it; everything that follows,
    /// including the writes, happens here. That keeps folder management
    /// identical wherever folder rows are shown.
    ///
    /// - Parameter action: The flow being presented, cleared when it finishes.
    /// - Returns: The view with the folder presentations attached.
    func folderActions(_ action: Binding<FolderAction?>) -> some View {
        modifier(FolderActionsModifier(action: action))
    }
}

/// Presents and performs folder creation, renaming, moving, and deletion.
///
/// Rules that decide anything live in ``FolderHierarchy``. What is left here is
/// presentation and the calls into the context, so the tree invariant cannot be
/// bypassed by a screen that forgets to check something.
private struct FolderActionsModifier: ViewModifier {
    @Binding var action: FolderAction?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nameDraft = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: action) { _, newAction in
                // The rename alert opens on the folder's current name, so the
                // draft is primed as the flow begins rather than when the
                // alert's body happens to run.
                nameDraft = newAction?.folder?.name ?? ""
            }
            .alert(namingTitle, isPresented: isNaming) {
                TextField("Name", text: $nameDraft)

                Button(namingConfirmTitle) {
                    confirmName()
                }
                .disabled(trimmedNameDraft.isEmpty)

                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete Folder?",
                isPresented: isDeleting,
                titleVisibility: .visible,
                presenting: deletingFolder
            ) { folder in
                Button("Delete Folder", role: .destructive) {
                    delete(folder)
                }

                Button("Cancel", role: .cancel) {}
            } message: { folder in
                Text(Self.deletionMessage(for: folder))
            }
            .sheet(item: movingFolder) { folder in
                FolderMovePickerView(folder: folder)
            }
    }

    // MARK: Presentation state

    /// Whether the current flow asks for a name.
    private var isNaming: Binding<Bool> {
        presence { action in
            switch action {
            case .create, .rename: true
            case .move, .delete: false
            }
        }
    }

    /// Whether the current flow is confirming a deletion.
    private var isDeleting: Binding<Bool> {
        presence { action in
            if case .delete = action { true } else { false }
        }
    }

    /// The folder being deleted, read by the confirmation dialog.
    private var deletingFolder: Folder? {
        if case let .delete(folder) = action { folder } else { nil }
    }

    /// The folder being moved, as the sheet's item.
    private var movingFolder: Binding<Folder?> {
        Binding {
            if case let .move(folder) = action { folder } else { nil }
        } set: { folder in
            if folder == nil {
                action = nil
            }
        }
    }

    /// Bridges the single action state to the boolean a presentation wants.
    ///
    /// - Parameter matches: Whether an action drives this presentation.
    /// - Returns: A binding that clears the action when the presentation ends.
    private func presence(
        _ matches: @escaping (FolderAction) -> Bool
    ) -> Binding<Bool> {
        Binding {
            action.map(matches) ?? false
        } set: { isPresented in
            if !isPresented {
                action = nil
            }
        }
    }

    private var namingTitle: String {
        if case .rename = action { "Rename Folder" } else { "New Folder" }
    }

    private var namingConfirmTitle: String {
        if case .rename = action { "Rename" } else { "Create" }
    }

    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Animation for rows arriving and leaving, honoring Reduce Motion.
    private var motion: Animation? {
        reduceMotion ? nil : Theme.Motion.reorder
    }

    // MARK: Writes

    /// Creates or renames a folder with the name that was typed.
    ///
    /// Renaming touches this folder and nothing else. Paths are derived from
    /// the parent chain rather than stored, so every descendant's displayed
    /// location follows without anything being rewritten.
    private func confirmName() {
        switch action {
        case let .create(parent):
            withAnimation(motion) {
                modelContext.insert(Folder(name: trimmedNameDraft, parent: parent))
            }

        case let .rename(folder):
            folder.name = trimmedNameDraft

        case .move, .delete, .none:
            break
        }

        action = nil
    }

    /// Deletes a folder, keeping its notes and its subfolders.
    ///
    /// - Parameter folder: The folder to remove.
    private func delete(_ folder: Folder) {
        withAnimation(motion) {
            FolderHierarchy.delete(folder, in: modelContext)
        }

        action = nil
    }

    /// Spells out what deleting a folder does to the things inside it.
    ///
    /// Both halves of the promotion rule are stated, because the one thing a
    /// user could reasonably fear here is losing writing or an entire branch of
    /// their organization, and neither happens.
    ///
    /// - Parameter folder: The folder about to be deleted.
    /// - Returns: Copy naming where its notes and subfolders end up.
    static func deletionMessage(for folder: Folder) -> String {
        var sentences: [String] = []
        let noteCount = folder.notes.count
        let childCount = folder.children.count

        switch noteCount {
        case 0: break
        case 1: sentences.append("1 note moves to Unfiled.")
        default: sentences.append("\(noteCount) notes move to Unfiled.")
        }

        if childCount > 0 {
            let subject = childCount == 1 ? "1 subfolder moves" : "\(childCount) subfolders move"

            if let parent = folder.parent {
                sentences.append("\(subject) into \(parent.displayName).")
            } else {
                sentences.append("\(subject) to the top level.")
            }
        }

        guard !sentences.isEmpty else {
            return "This folder is empty."
        }

        return sentences.joined(separator: " ")
    }
}
