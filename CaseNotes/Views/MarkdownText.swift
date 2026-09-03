//
//  MarkdownText.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// Renders a Markdown note body for reading.
///
/// Block layout comes from ``MarkdownDocument``. This view owns presentation
/// only: fonts, indentation, and the small amount of decoration that headings,
/// lists, quotes, and code blocks need. Inline styling is resolved explicitly
/// per run rather than left to `Text`, so bold, italic, and inline code look the
/// same wherever they appear.
///
/// A thematic break becomes a control that folds the region below it away.
/// Folding is presentation and nothing else: the source is never rewritten, no
/// marker is stored, and the editor keeps showing every character of the note,
/// which is what leaves native selection and Select All intact.
struct MarkdownText: View {
    let source: String

    /// The parse, kept across updates.
    ///
    /// Parsing is the expensive part of showing a note, and a reading view is
    /// re-evaluated for reasons that have nothing to do with its text, such as
    /// presenting a sheet. The cache is a reference type on purpose:
    /// `State(initialValue:)` evaluates its argument on every initializer call
    /// and then discards all but the first, so holding the document itself in
    /// state would still parse the note on every update.
    @State private var cache = ParsedMarkdown()

    /// The regions currently folded away, held by section identity.
    ///
    /// Reading state and nothing more. It lives for as long as this view does,
    /// is never written to the store, and is deliberately cleared when the
    /// source changes: identity is a region's position, so keeping it across an
    /// edit could fold a region the reader never chose.
    @State private var collapsedSections: Set<Int> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let sections = cache.document(for: source).sections

        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                sectionView(for: section)
            }
        }
        .onChange(of: source) {
            collapsedSections = []
        }
    }

    /// Lays out one region: its divider, when it has one, and its content.
    ///
    /// A folded region is removed from the view tree rather than hidden, so
    /// VoiceOver does not read text the screen is not showing.
    ///
    /// - Parameter section: The region to lay out.
    /// - Returns: The divider and content for that region.
    @ViewBuilder
    private func sectionView(for section: MarkdownDocument.Section) -> some View {
        if section.precededByThematicBreak {
            if section.blocks.isEmpty {
                // Two breaks in a row, or a break ending the note. The divider
                // is authored, so it still renders, but there is nothing under
                // it to fold and therefore no control to offer.
                MarkdownThematicRule()
                    .padding(.vertical, Theme.Spacing.medium)
            } else {
                sectionDivider(for: section)
            }
        }

        if !collapsedSections.contains(section.id) {
            MarkdownBlockStack(blocks: section.blocks)
        }
    }

    /// The control that folds a region away and brings it back.
    ///
    /// A hairline with a chevron rather than a button between paragraphs: the
    /// divider the author wrote is the affordance, so reading a note that is
    /// never folded looks the way it always did. The row is quiet but keeps a
    /// full-height target, and the collapsed state is spoken as a value rather
    /// than left to the chevron's direction.
    ///
    /// The written hint is dropped at accessibility text sizes, where it would
    /// truncate and leave the hairline as a stub. The chevron and the spoken
    /// value both still report the state, so nothing is lost by removing it.
    ///
    /// - Parameter section: The region the control folds.
    /// - Returns: The divider row.
    private func sectionDivider(for section: MarkdownDocument.Section) -> some View {
        let isCollapsed = collapsedSections.contains(section.id)

        return Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.reorder) {
                if isCollapsed {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                MarkdownThematicRule()

                if isCollapsed, !dynamicTypeSize.isAccessibilitySize {
                    Text("Section collapsed")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(minHeight: Theme.Layout.minimumRowHeight)
            .padding(.vertical, Theme.Spacing.xSmall)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand section" : "Collapse section")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }
}

#Preview {
    ScrollView {
        MarkdownText(
            source: """
            # Site Visit

            Walked the north wing with **facilities**. The stairwell lighting is \
            still out and the east door does not *latch*.

            ## Actions

            - Photograph the stairwell
            - Check the ramp handrail

            1. Raise a ticket
            2. Confirm the schedule

            > Parts are on order.

            ---

            ## Follow Up

            Use `notes.export()` or see the [handbook](https://example.com).

            ```swift
            let note = Note(title: "Site Visit")
            ```

            ---

            Confirm the schedule with the contractor.
            """
        )
        .padding()
    }
    .background(Theme.Colors.canvas)
}
