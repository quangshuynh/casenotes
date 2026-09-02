//
//  MarkdownEditingMode.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import Foundation

/// How a note's Markdown is presented while the editor is open.
///
/// The three modes differ in what they show, never in what they store. The
/// stored body is the Markdown source in all of them, switching between them
/// rewrites nothing, and a mode is ephemeral view state: it is not persisted,
/// not part of ``NoteDraft``, and cannot move a note's edit timestamp or write
/// a version.
enum MarkdownEditingMode: String, CaseIterable, Identifiable, Sendable {
    /// The draft rendered the way the note screen renders it, not editable.
    case reading

    /// Rendered Markdown that exposes the source of the region holding the
    /// caret, so a note can be read and written in the same place.
    case livePreview

    /// The complete Markdown source in one editable field.
    case source

    var id: String {
        rawValue
    }

    /// The name of the mode as the interface spells it.
    var title: String {
        switch self {
        case .reading: "Reading"
        case .livePreview: "Live Preview"
        case .source: "Source"
        }
    }

    /// The SF Symbol that accompanies the name.
    ///
    /// Always shown beside the title rather than instead of it, so the active
    /// mode is never carried by a glyph or a tint alone.
    var symbolName: String {
        switch self {
        case .reading: "book"
        case .livePreview: "doc.richtext"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// What the mode does, for the picker's accessibility hint.
    var summary: String {
        switch self {
        case .reading: "Rendered Markdown, not editable"
        case .livePreview: "Rendered Markdown, editable one region at a time"
        case .source: "The complete Markdown source, editable"
        }
    }

    /// The footer under the body field, which says what the mode does with
    /// Markdown rather than repeating the mode's own name.
    var footer: String {
        switch self {
        case .reading:
            "The draft rendered as it will read. Switch to Live Preview or Source to make changes."
        case .livePreview:
            "Markdown renders as you write. Tap a paragraph, heading, list, quote, or code block to edit its source."
        case .source:
            "Markdown is supported. Use # for headings, * for emphasis, - for lists, > for quotes, and backticks for code."
        }
    }

    /// Whether the body can be typed into in this mode.
    var isEditable: Bool {
        self != .reading
    }

    /// The mode the editor opens in.
    ///
    /// Editing a note is the common reason to open the editor, and live preview
    /// is the mode that keeps a note legible while it is being written. Source
    /// stays one selection away for anyone who would rather see every character.
    static let `default` = MarkdownEditingMode.livePreview
}
