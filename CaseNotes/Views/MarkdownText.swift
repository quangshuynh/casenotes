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
                thematicRule
                    .padding(.vertical, Theme.Spacing.medium)
            } else {
                sectionDivider(for: section)
            }
        }

        if !collapsedSections.contains(section.id) {
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { index, block in
                blockView(for: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(
                        .top,
                        index == 0
                            ? 0
                            : spacingAbove(block, previous: section.blocks[index - 1])
                    )
            }
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
                thematicRule

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

    /// The hairline a thematic break draws.
    private var thematicRule: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
    }

    /// The gap to leave above a block.
    ///
    /// Consecutive list items sit closer together than separate blocks do, so a
    /// list reads as one group rather than as a stack of loose paragraphs.
    ///
    /// - Parameters:
    ///   - block: The block about to be laid out.
    ///   - previous: The block above it within the same region.
    /// - Returns: The leading padding in points.
    private func spacingAbove(
        _ block: MarkdownDocument.Block,
        previous: MarkdownDocument.Block
    ) -> CGFloat {
        if case .listItem = block, case .listItem = previous {
            return Theme.Spacing.small
        }

        return Theme.Spacing.medium
    }

    /// Lays out one parsed block.
    ///
    /// - Parameter block: The block to render.
    /// - Returns: The view for that block, styled for reading.
    @ViewBuilder
    private func blockView(for block: MarkdownDocument.Block) -> some View {
        switch block {
        case let .paragraph(text):
            Text(styled(text, base: .body))
                .lineSpacing(Theme.Spacing.xSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)

        case let .heading(level, text):
            Text(styled(text, base: headingFont(for: level)))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.top, Theme.Spacing.xSmall)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

        case let .listItem(ordinal, depth, text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                Text(ordinal.map { "\($0)." } ?? "\u{2022}")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.accent)

                Text(styled(text, base: .body))
                    .lineSpacing(Theme.Spacing.xSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.leading, CGFloat(depth) * Theme.Spacing.large)
            .textSelection(.enabled)

        case let .blockQuote(text):
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: 3)

                Text(styled(text, base: .body))
                    .italic()
                    .lineSpacing(Theme.Spacing.xSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

        case let .codeBlock(language, code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(Theme.Spacing.medium)
            .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.small))
            .accessibilityLabel(
                language.map { "Code block in \($0)" } ?? "Code block"
            )

        case .thematicBreak:
            // Regions consume every break before rendering reaches here, so
            // this case exists to keep the switch total.
            thematicRule
                .padding(.vertical, Theme.Spacing.xSmall)
        }
    }

    /// Resolves inline Markdown intent into concrete fonts.
    ///
    /// - Parameters:
    ///   - text: A block's text, still carrying inline presentation intent.
    ///   - base: The font the block is set in.
    /// - Returns: The text with a font applied to every run.
    private func styled(
        _ text: AttributedString,
        base: Font
    ) -> AttributedString {
        var styled = text

        for run in styled.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = base

            if intent.contains(.code) {
                font = .system(.callout, design: .monospaced)
            }
            if intent.contains(.stronglyEmphasized) {
                font = font.bold()
            }
            if intent.contains(.emphasized) {
                font = font.italic()
            }

            styled[run.range].font = font
        }

        return styled
    }

    /// Maps a Markdown heading level onto a text style.
    ///
    /// Levels beyond three share one style, since notes rarely nest deeper and
    /// smaller steps stop reading as headings at all.
    ///
    /// - Parameter level: The heading level, starting at one.
    /// - Returns: The font for that level.
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
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
