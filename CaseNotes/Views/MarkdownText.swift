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

    var body: some View {
        let blocks = cache.document(for: source).blocks

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(for: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(
                        .top,
                        spacingAbove(block, previous: index > 0 ? blocks[index - 1] : nil)
                    )
            }
        }
    }

    /// The gap to leave above a block.
    ///
    /// Consecutive list items sit closer together than separate blocks do, so a
    /// list reads as one group rather than as a stack of loose paragraphs.
    ///
    /// - Parameters:
    ///   - block: The block about to be laid out.
    ///   - previous: The block above it, or `nil` for the first block.
    /// - Returns: The leading padding in points.
    private func spacingAbove(
        _ block: MarkdownDocument.Block,
        previous: MarkdownDocument.Block?
    ) -> CGFloat {
        guard let previous else {
            return 0
        }

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
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
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

            Use `notes.export()` or see the [handbook](https://example.com).

            ```swift
            let note = Note(title: "Site Visit")
            ```
            """
        )
        .padding()
    }
    .background(Theme.Colors.canvas)
}
