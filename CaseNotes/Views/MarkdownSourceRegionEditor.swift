//
//  MarkdownSourceRegionEditor.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import SwiftUI
import UIKit

/// Where the caret should be put when a region becomes the one being edited.
///
/// A request is applied once and then cleared by the view that made it, which
/// is what stops a stale position fighting the user's own typing.
struct MarkdownCaretRequest: Equatable {
    /// Where to place the caret.
    enum Target: Equatable {
        /// A position measured in UTF-16 code units from the start of the
        /// region's source.
        case offset(Int)

        /// A point in the region's own coordinate space, resolved by asking the
        /// text view which position is nearest to it.
        ///
        /// This is what a tap on rendered Markdown produces. The rendered block
        /// and the editor that replaces it occupy the same slot with the same
        /// width and the same block font, so the point means very nearly the
        /// same thing in both, and the answer comes from real text layout
        /// rather than from counting characters.
        case point(CGPoint)
    }

    /// Distinguishes one request from the next so an identical target asked for
    /// twice is still honoured twice.
    let id: Int

    let target: Target
}

/// Where the note body was last being edited, shared without redrawing.
///
/// A reference type on purpose. The caret moves on every keystroke and on every
/// tap, and the one thing that reads it, the action that places an attachment,
/// runs long after the movement that set it. Holding it in SwiftUI state would
/// therefore redraw the whole editor for a value nothing on screen depends on,
/// on the one path this app has already lost characters to.
///
/// It is deliberately not cleared when editing stops. Choosing a file dismisses
/// the keyboard, so the position an attachment is placed at is always one the
/// editor stopped tracking a moment earlier.
final class MarkdownBodyCaret {
    /// The caret's place in the body, in UTF-16 code units, or `nil` when the
    /// body has not been edited yet.
    var utf16Offset: Int?
}

/// A reshaping of the text a region editor holds.
///
/// A region can stop being the right unit while it is being typed into: a blank
/// line turns one paragraph into two, and a delete at the start joins two blocks
/// into one. The owner works that out and hands back the text the view should
/// now hold, which the view applies to itself in the same event that caused it.
///
/// Doing it this way, rather than by letting the owner push new text on the next
/// redraw, is what keeps typing safe. Keys arriving faster than SwiftUI redraws
/// would otherwise be overwritten by a value computed before they were pressed,
/// which cost real text when it was typed quickly into a long note.
struct MarkdownRegionReshape: Equatable {
    /// The source the region now holds.
    let text: String

    /// Where the caret belongs in it, in UTF-16 code units.
    let caret: Int
}

/// The editable source of one Markdown region.
///
/// SwiftUI's `TextEditor` exposes neither the caret's position nor a way to put
/// it somewhere, and live preview needs both: a tap on rendered text has to
/// arrive somewhere sensible in the source, and the caret's position decides
/// which region is being edited. This is therefore a deliberately small UIKit
/// bridge over `UITextView` and nothing more. It holds one region's characters,
/// reports what was typed and where the caret is, and leaves every decision
/// about Markdown to its caller.
///
/// It is not a rich text editor. The text it holds is plain Markdown source in
/// one font, editing is the system's own, and no attribute is ever written into
/// the storage.
struct MarkdownSourceRegionEditor: UIViewRepresentable {
    /// The region's source, exactly as it is stored in the draft.
    let text: String

    /// The font the region's leading block is set in, so a heading being edited
    /// still looks like a heading with its syntax showing.
    let font: UIFont

    /// A caret placement waiting to be applied, if any.
    let caretRequest: MarkdownCaretRequest?

    /// Reports the text view's contents and caret.
    ///
    /// - Parameters:
    ///   - text: What the view now holds.
    ///   - caret: The caret's position in UTF-16 code units from the start of
    ///     the region.
    ///   - isEdit: Whether the text itself changed, as opposed to the caret
    ///     merely moving.
    /// - Returns: A reshaping to apply at once when the edit changed which
    ///   region the caret is in, or `nil` when the region still stands.
    let onChange: (_ text: String, _ caret: Int, _ isEdit: Bool) -> MarkdownRegionReshape?

    /// Called when the user presses delete with the caret at the very start of
    /// the region, which is a request to join this region to the one above it.
    ///
    /// The keystroke is always consumed here, because deleting backwards from
    /// position zero of a region's own text would otherwise do nothing at all.
    ///
    /// - Returns: The joined region, or `nil` when there was nothing above to
    ///   join it to.
    let onDeleteBackwardAtStart: () -> MarkdownRegionReshape?

    /// Called when the region stops being edited, usually because the keyboard
    /// was dismissed.
    let onEndEditing: () -> Void

    /// Called once a caret request has been applied.
    let onCaretRequestHandled: () -> Void

    func makeUIView(context: Context) -> SourceRegionTextView {
        let view = SourceRegionTextView()

        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(Theme.Colors.textPrimary)
        view.tintColor = UIColor(Theme.Colors.accent)
        view.font = font
        view.text = text
        view.accessibilityLabel = "Markdown source"
        view.accessibilityHint = "Editing the region under the cursor"
        view.onDeleteBackwardAtStart = onDeleteBackwardAtStart
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.required, for: .vertical)

        // Autocorrection and smart punctuation are left at the system defaults
        // on purpose, so the two editable modes behave identically and so no
        // note loses spelling help to make one Markdown spelling easier to type.
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }

        return view
    }

    func updateUIView(_ uiView: SourceRegionTextView, context: Context) {
        context.coordinator.parent = self
        uiView.onDeleteBackwardAtStart = onDeleteBackwardAtStart

        if uiView.font != font {
            uiView.font = font
        }

        // A view composing with an input method owns its own text until the
        // composition finishes, so replacing it underneath would drop what is
        // being typed.
        if uiView.markedTextRange == nil, uiView.text != text {
            let caret = uiView.selectedRange.location

            context.coordinator.isApplyingExternalText = true
            uiView.text = text
            context.coordinator.isApplyingExternalText = false

            // The text arrived from outside this view, so anything the undo
            // stack still holds refers to characters that are no longer here.
            uiView.undoManager?.removeAllActions()

            let clamped = min(caret, (text as NSString).length)
            uiView.selectedRange = NSRange(location: clamped, length: 0)
        }

        guard let caretRequest, context.coordinator.appliedCaretRequestID != caretRequest.id else {
            return
        }

        context.coordinator.appliedCaretRequestID = caretRequest.id

        // Layout has not run for a view that has only just been created, so the
        // point form of a request has nothing to resolve against yet.
        DispatchQueue.main.async {
            apply(caretRequest, to: uiView)
            onCaretRequestHandled()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: SourceRegionTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else {
            return nil
        }

        let fitted = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )

        return CGSize(width: width, height: max(fitted.height, font.lineHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Puts the caret where a request asks for it and takes the keyboard.
    ///
    /// - Parameters:
    ///   - request: The placement being honoured.
    ///   - view: The text view holding the region.
    private func apply(_ request: MarkdownCaretRequest, to view: SourceRegionTextView) {
        let length = (view.text as NSString).length

        switch request.target {
        case let .offset(offset):
            view.selectedRange = NSRange(location: min(max(offset, 0), length), length: 0)

        case let .point(point):
            // A region owns the blank lines that separate it from the next
            // block, so a tap below the last line of rendered text resolves
            // into empty space. A tap on rendered content means a position in
            // that content, so it is held back to the end of it. Reaching the
            // blank lines is still possible, by moving the caret there.
            let contentEnd = (view.text.replacingOccurrences(
                of: "\\s+$",
                with: "",
                options: .regularExpression
            ) as NSString).length

            if let position = view.closestPosition(to: point) {
                let offset = view.offset(from: view.beginningOfDocument, to: position)
                view.selectedRange = NSRange(
                    location: min(max(offset, 0), max(contentEnd, 0)),
                    length: 0
                )
            } else {
                view.selectedRange = NSRange(location: min(contentEnd, length), length: 0)
            }
        }

        if !view.isFirstResponder {
            view.becomeFirstResponder()
        }

        view.scrollRangeToVisible(view.selectedRange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownSourceRegionEditor

        /// The last request honoured, so a redraw does not move the caret again.
        var appliedCaretRequestID: Int?

        /// Set while text is being written in from the outside, so the resulting
        /// delegate callbacks are not mistaken for the user typing.
        var isApplyingExternalText = false

        init(parent: MarkdownSourceRegionEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalText else {
                return
            }

            let reshape = parent.onChange(textView.text, textView.selectedRange.location, true)

            (textView as? SourceRegionTextView)?.apply(reshape)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingExternalText else {
                return
            }

            let reshape = parent.onChange(textView.text, textView.selectedRange.location, false)

            (textView as? SourceRegionTextView)?.apply(reshape)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onEndEditing()
        }
    }
}

/// A text view that can hand a delete at the start of its text back to its
/// owner.
///
/// A region holds only its own characters, so deleting backwards from its first
/// position would otherwise do nothing at all and leave two blocks impossible to
/// join. `deleteBackward()` is the one place UIKit routes that gesture through,
/// whether it came from the software keyboard, a hardware keyboard, or an
/// accessibility action, which is why the behavior lives here rather than in a
/// text-change callback that never fires for a deletion of nothing.
final class SourceRegionTextView: UITextView {
    /// Consulted when delete is pressed with an empty selection at position
    /// zero, and answered with the joined region when there was one above.
    var onDeleteBackwardAtStart: (() -> MarkdownRegionReshape?)?

    override func deleteBackward() {
        guard selectedRange.location == 0, selectedRange.length == 0 else {
            super.deleteBackward()
            return
        }

        // Deleting backwards from position zero of a region's own text would do
        // nothing, so the keystroke is consumed either way: it either joined
        // this region to the one above it or there was nothing above.
        apply(onDeleteBackwardAtStart?())
    }

    /// Takes on the text a reshaping asks for, without reporting it back.
    ///
    /// Setting `text` does not call the delegate, so the owner is not told about
    /// a change it just asked for.
    ///
    /// - Parameter reshape: What to hold now, or `nil` to leave the text alone.
    func apply(_ reshape: MarkdownRegionReshape?) {
        guard let reshape else {
            return
        }

        if text != reshape.text {
            text = reshape.text
            undoManager?.removeAllActions()
        }

        let length = (text as NSString).length

        selectedRange = NSRange(location: min(max(reshape.caret, 0), length), length: 0)
    }
}
