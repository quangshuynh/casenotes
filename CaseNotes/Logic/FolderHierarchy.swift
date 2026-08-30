//
//  FolderHierarchy.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import Foundation
import SwiftData

/// The rules that keep the folder graph a tree, and the derived answers the
/// interface needs from it.
///
/// SwiftData stores a self-referential relationship without policing its shape:
/// assigning two folders as each other's parent is accepted, saved, and
/// reopened. The tree invariant therefore lives here rather than in the model,
/// and every move goes through ``move(_:to:)`` so a cycle cannot be created
/// through the app at all. Traversal still carries a visited guard, because
/// code that walks a graph must terminate on data it did not create.
///
/// Nothing here writes to a note. Hierarchy is organization: moving, renaming,
/// and deleting folders never touch authored content, `updatedAt`, or version
/// history.
enum FolderHierarchy {
    /// Separator between the folders of a displayed path.
    static let pathSeparator = " › "

    // MARK: Traversal

    /// The folders a folder sits inside, nearest first.
    ///
    /// - Parameter folder: The folder to walk up from.
    /// - Returns: Its parent, then that folder's parent, up to the root. Empty
    ///   for a root folder.
    static func ancestors(of folder: Folder) -> [Folder] {
        var result: [Folder] = []
        var visited: Set<PersistentIdentifier> = [folder.persistentModelID]
        var current = folder.parent

        while let next = current, visited.insert(next.persistentModelID).inserted {
            result.append(next)
            current = next.parent
        }

        return result
    }

    /// Every folder inside a folder, at any depth.
    ///
    /// Breadth first, so the nearest descendants come first. The visited guard
    /// is what keeps malformed data from looping rather than an expectation
    /// that it exists.
    ///
    /// - Parameter folder: The folder to walk down from.
    /// - Returns: All descendants, excluding the folder itself.
    static func descendants(of folder: Folder) -> [Folder] {
        var result: [Folder] = []
        var visited: Set<PersistentIdentifier> = [folder.persistentModelID]
        var queue = folder.children

        while !queue.isEmpty {
            let next = queue.removeFirst()

            guard visited.insert(next.persistentModelID).inserted else {
                continue
            }

            result.append(next)
            queue.append(contentsOf: next.children)
        }

        return result
    }

    /// Whether one folder sits somewhere inside another.
    ///
    /// - Parameters:
    ///   - candidate: The folder that might be inside.
    ///   - folder: The folder that might contain it.
    /// - Returns: `true` when `candidate` is a descendant at any depth. A
    ///   folder is not a descendant of itself.
    static func isDescendant(_ candidate: Folder, of folder: Folder) -> Bool {
        let target = candidate.persistentModelID
        var visited: Set<PersistentIdentifier> = [folder.persistentModelID]
        var queue = folder.children

        while !queue.isEmpty {
            let next = queue.removeFirst()

            guard visited.insert(next.persistentModelID).inserted else {
                continue
            }

            if next.persistentModelID == target {
                return true
            }

            queue.append(contentsOf: next.children)
        }

        return false
    }

    // MARK: Moving

    /// Whether a folder may be filed inside another.
    ///
    /// The two rejections are the whole tree invariant: a folder cannot contain
    /// itself, and it cannot be filed into its own subtree, which would cut that
    /// subtree loose in a cycle. Moving to the library root is always allowed.
    ///
    /// - Parameters:
    ///   - folder: The folder being moved.
    ///   - proposedParent: The folder it would move into, or `nil` for the
    ///     library root.
    /// - Returns: `true` when the move keeps the graph a tree.
    static func canMove(_ folder: Folder, to proposedParent: Folder?) -> Bool {
        guard let proposedParent else {
            return true
        }

        guard proposedParent.persistentModelID != folder.persistentModelID else {
            return false
        }

        return !isDescendant(proposedParent, of: folder)
    }

    /// Files a folder inside another, refusing a move that would break the tree.
    ///
    /// Validation lives here rather than in the picker so an invalid move is
    /// impossible rather than merely unavailable. Only the hierarchy changes:
    /// the folder keeps its notes, its own children come with it, and no note
    /// is touched.
    ///
    /// - Parameters:
    ///   - folder: The folder being moved.
    ///   - newParent: The destination folder, or `nil` for the library root.
    /// - Returns: `true` when the move was applied, `false` when it was refused.
    @discardableResult
    static func move(_ folder: Folder, to newParent: Folder?) -> Bool {
        guard canMove(folder, to: newParent) else {
            return false
        }

        folder.parent = newParent

        return true
    }

    // MARK: Deleting

    /// Deletes one folder, keeping everything it held.
    ///
    /// Folders organize notes rather than own them, so deleting one destroys no
    /// writing and no subtree. Direct notes become Unfiled and direct children
    /// move up into the deleted folder's own parent, which for a root folder
    /// means they become root folders. Descendants deeper than one level are
    /// untouched: a note two levels down stays exactly where it was.
    ///
    /// The promotion happens before the delete rather than being left to the
    /// relationship's nullify rule, which would scatter every child to the root.
    /// Both sides are gathered into arrays first, because assigning a new parent
    /// mutates the relationship being iterated.
    ///
    /// - Parameters:
    ///   - folder: The folder to remove.
    ///   - context: The context the folder belongs to.
    static func delete(_ folder: Folder, in context: ModelContext) {
        let inheritedParent = folder.parent

        for child in Array(folder.children) {
            child.parent = inheritedParent
        }

        for note in Array(folder.notes) {
            note.folder = nil
        }

        context.delete(folder)
    }

    // MARK: Paths

    /// The names of every folder from the root down to this one.
    ///
    /// - Parameter folder: The folder to describe.
    /// - Returns: Display names, outermost first, ending with this folder.
    static func pathComponents(of folder: Folder) -> [String] {
        ancestors(of: folder).reversed().map(\.displayName) + [folder.displayName]
    }

    /// Where a folder sits, written as a path.
    ///
    /// Deep paths are shortened from the front rather than allowed to grow
    /// without limit, because the folders nearest the destination are the ones
    /// that identify it.
    ///
    /// - Parameters:
    ///   - folder: The folder to describe.
    ///   - maximumComponents: How many names the path may name before it is
    ///     shortened with a leading ellipsis.
    /// - Returns: A path such as `Work › Project Alpha › Research`.
    static func pathText(of folder: Folder, maximumComponents: Int = 4) -> String {
        shortened(pathComponents(of: folder), to: maximumComponents)
    }

    /// Where a folder sits, naming only the folders above it.
    ///
    /// - Parameters:
    ///   - folder: The folder to describe.
    ///   - maximumComponents: How many names the path may name before it is
    ///     shortened with a leading ellipsis.
    /// - Returns: A path such as `Work › Project Alpha`, or `nil` for a root
    ///   folder, which has nothing above it to name.
    static func locationText(of folder: Folder, maximumComponents: Int = 3) -> String? {
        let components = ancestors(of: folder).reversed().map(\.displayName)

        guard !components.isEmpty else {
            return nil
        }

        return shortened(Array(components), to: maximumComponents)
    }

    /// Where a folder sits, spoken rather than drawn.
    ///
    /// VoiceOver gets the location in full, with ordinary commas instead of the
    /// path separator, so hierarchy never depends on hearing a symbol read out.
    ///
    /// - Parameter folder: The folder to describe.
    /// - Returns: A phrase such as `inside Work, Project Alpha`, or `nil` for a
    ///   root folder.
    static func spokenLocation(of folder: Folder) -> String? {
        let components = ancestors(of: folder).reversed().map(\.displayName)

        guard !components.isEmpty else {
            return nil
        }

        return "inside \(components.joined(separator: ", "))"
    }

    /// Joins path components, dropping the outermost ones when there are too
    /// many to show.
    ///
    /// - Parameters:
    ///   - components: Folder names, outermost first.
    ///   - limit: The largest number of names to keep.
    /// - Returns: The joined path, prefixed with an ellipsis when shortened.
    private static func shortened(_ components: [String], to limit: Int) -> String {
        guard limit > 1, components.count > limit else {
            return components.joined(separator: pathSeparator)
        }

        let kept = components.suffix(limit - 1)

        return (["…"] + kept).joined(separator: pathSeparator)
    }

    // MARK: Ordering

    /// Puts folders in the order the interface shows them in.
    ///
    /// Name order, matching the rest of the app. The creation date breaks ties
    /// so two folders sharing a name cannot swap places between updates, since
    /// names are not required to be unique.
    ///
    /// - Parameter folders: The folders to order.
    /// - Returns: The same folders, ordered for display.
    static func ordered(_ folders: [Folder]) -> [Folder] {
        folders.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCompare(rhs.displayName)

            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }

            return lhs.createdAt < rhs.createdAt
        }
    }
}

/// One place a folder or a note can be moved to, ready to draw in a picker.
///
/// The depth is what a list indents by and the path is what disambiguates two
/// folders sharing a name. Both are worked out once while the tree is walked,
/// so a picker row costs no traversal of its own.
struct FolderDestination: Identifiable, Hashable {
    /// The folder being offered.
    let folder: Folder

    /// How many folders sit above this one, zero at the library root.
    let depth: Int

    /// The full path to this folder, used where a name alone is ambiguous.
    let pathText: String

    var id: PersistentIdentifier { folder.persistentModelID }

    /// The folder's own name.
    var name: String { folder.displayName }

    /// The row spoken in full, naming the folders it sits inside.
    var spokenDescription: String {
        guard let location = FolderHierarchy.spokenLocation(of: folder) else {
            return "\(name), top level"
        }

        return "\(name), \(location)"
    }
}

/// Every folder grouped by the folder it sits in, worked out in one pass.
///
/// Browsing screens and pickers all need the same three answers: what sits at
/// the root, what sits inside a given folder, and how many folders a row
/// contains. Reading those from the relationship on each row would fault a
/// separate array per row, so the whole set is grouped once from the folders a
/// screen has already fetched.
struct FolderTree {
    /// Root folders, in display order.
    let roots: [Folder]

    private let childrenByParent: [PersistentIdentifier: [Folder]]

    /// - Parameter folders: Every folder in the store, in any order.
    init(_ folders: [Folder]) {
        var roots: [Folder] = []
        var grouped: [PersistentIdentifier: [Folder]] = [:]

        for folder in folders {
            if let parent = folder.parent {
                grouped[parent.persistentModelID, default: []].append(folder)
            } else {
                roots.append(folder)
            }
        }

        self.roots = FolderHierarchy.ordered(roots)
        self.childrenByParent = grouped.mapValues { FolderHierarchy.ordered($0) }
    }

    /// The folders sitting directly inside one folder, in display order.
    ///
    /// - Parameter folder: The folder to look inside.
    /// - Returns: Its direct children, empty when it has none.
    func children(of folder: Folder) -> [Folder] {
        childrenByParent[folder.persistentModelID] ?? []
    }

    /// How many folders sit directly inside one folder.
    ///
    /// - Parameter folder: The folder to look inside.
    /// - Returns: The number of direct children, not counting deeper ones.
    func childCount(of folder: Folder) -> Int {
        children(of: folder).count
    }

    /// Every folder in tree order, ready to offer as a destination.
    ///
    /// A folder cannot be moved into itself or into its own subtree, so passing
    /// the folder being moved removes exactly the destinations that would break
    /// the tree. The same walk with nothing excluded is what a note's move
    /// picker offers, since a note can be filed anywhere.
    ///
    /// - Parameter excluded: A folder whose subtree, itself included, is left
    ///   out. Pass `nil` to offer every folder.
    /// - Returns: Destinations in the order the tree reads, outermost first.
    func destinations(excludingSubtreeOf excluded: Folder? = nil) -> [FolderDestination] {
        var result: [FolderDestination] = []
        var visited: Set<PersistentIdentifier> = []

        func walk(_ folders: [Folder], depth: Int, prefix: [String]) {
            for folder in folders {
                guard folder.persistentModelID != excluded?.persistentModelID else {
                    continue
                }

                guard visited.insert(folder.persistentModelID).inserted else {
                    continue
                }

                let path = prefix + [folder.displayName]

                result.append(
                    FolderDestination(
                        folder: folder,
                        depth: depth,
                        pathText: path.joined(separator: FolderHierarchy.pathSeparator)
                    )
                )

                walk(children(of: folder), depth: depth + 1, prefix: path)
            }
        }

        walk(roots, depth: 0, prefix: [])

        return result
    }
}
