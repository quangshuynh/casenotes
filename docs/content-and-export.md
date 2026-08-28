# Content and Export

## Markdown storage and rendering

The note body is stored as its original Markdown source. Reading mode parses it
with Foundation `AttributedString` and reconstructs block structure from
`PresentationIntent` for SwiftUI layout.

Supported presentation includes headings, paragraphs, bold, italic, inline
code, links, ordered and unordered lists with nesting, block quotes, fenced code
blocks, and thematic breaks. Hand-authored line breaks remain visible.

Parsing requests a partial result for malformed input. If parsing still fails,
the renderer presents the source as plain text so content remains readable.

## List previews

Rows show a compact plain-text preview with Markdown syntax removed. Only the
opening fragment is parsed because the row can display only a small amount of
text. Whitespace is collapsed to a single line.

## Export contract

The exporter accepts injected locale and time-zone values so date output is
deterministic in tests. The generated document contains:

1. The note title as a Markdown heading.
2. The event date, when present.
3. The stored body without rewriting it.
4. A text notice when a drawing is attached.

Creation and edit timestamps, folder membership, and pinned state stay private
to application bookkeeping. Drawings are not embedded in the Markdown file.
