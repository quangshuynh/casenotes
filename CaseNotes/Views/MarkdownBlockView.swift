//
//  MarkdownBlockView.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import SwiftUI

/// The hairline a thematic break draws.
///
/// Shared so a divider looks the same whether it is read, folded, or sitting
/// between two regions of a note being edited.
struct MarkdownThematicRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
    }
}

/// One parsed Markdown block, laid out for reading.
///
/// This is the only place a block becomes pixels. ``MarkdownText`` renders a
/// note through it and so does live preview, which is what keeps a paragraph
/// looking the same the instant the caret leaves it as it did while it was
/// merely being read. A placed attachment is a block like any other, and the
/// note's files reach it through ``EnvironmentValues/inlineAttachments``.
struct MarkdownBlockView: View {
    let block: MarkdownDocument.Block

    var body: some View {
        switch block {
        case let .paragraph(text):
            Text(Self.styled(text, base: .body))
                .lineSpacing(Theme.Spacing.xSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)

        case let .heading(level, text):
            Text(Self.styled(text, base: Self.headingFont(for: level)))
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

                Text(Self.styled(text, base: .body))
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

                Text(Self.styled(text, base: .body))
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
            MarkdownThematicRule()
                .padding(.vertical, Theme.Spacing.xSmall)

        case let .attachment(id):
            InlineAttachmentBlockView(id: id)
        }
    }

    /// Resolves inline Markdown intent into concrete fonts.
    ///
    /// - Parameters:
    ///   - text: A block's text, still carrying inline presentation intent.
    ///   - base: The font the block is set in.
    /// - Returns: The text with a font applied to every run.
    static func styled(_ text: AttributedString, base: Font) -> AttributedString {
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
    static func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

/// A run of blocks laid out in reading order with the spacing they expect.
///
/// Consecutive list items sit closer together than separate blocks do, so a
/// list reads as one group rather than as a stack of loose paragraphs.
struct MarkdownBlockStack: View {
    let blocks: [MarkdownDocument.Block]

    var body: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
            MarkdownBlockView(block: block)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A block keeps its ideal height rather than accepting a
                // shorter offer. Reading sits in a scroll view and is never
                // offered one, but live preview sits in a form row beside a
                // text view that states an exact height, and prose there was
                // being compressed until it truncated mid-sentence.
                .fixedSize(horizontal: false, vertical: true)
                .padding(
                    .top,
                    index == 0 ? 0 : Self.spacingAbove(block, previous: blocks[index - 1])
                )
        }
    }

    /// The gap to leave above a block.
    ///
    /// - Parameters:
    ///   - block: The block about to be laid out.
    ///   - previous: The block above it.
    /// - Returns: The leading padding in points.
    static func spacingAbove(
        _ block: MarkdownDocument.Block,
        previous: MarkdownDocument.Block
    ) -> CGFloat {
        if case .listItem = block, case .listItem = previous {
            return Theme.Spacing.small
        }

        return Theme.Spacing.medium
    }
}
