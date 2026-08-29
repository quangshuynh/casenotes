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

![Reading view rendering a heading, bold and italic text, a bulleted list, a
block quote, and inline code](screenshots/note-markdown-dark.png){ width="300" }

## Collapsible sections in read mode

A thematic break divides a note into regions that read mode can fold. Each break
becomes a divider carrying a collapse control, and it owns the content after it
up to the next break or the end of the note, so folding one region never hides
another. Content written before the first break has no divider of its own and is
always visible.

Every thematic break the parser recognizes behaves the same way, whether it is
written as `---`, `***`, `___`, or a spaced variant. Recognition comes from the
parsed document rather than from matching lines of text, so a rule inside a
fenced or indented code block stays code, and a line of dashes under a line of
text stays the setext heading Markdown says it is.

Folding is presentation only:

- The stored Markdown is never rewritten, and no marker is added to it.
- The editor always shows the complete source, including every break.
- Collapsing does not change the note's edit time and records no version.
- Copy, share, and file export always use the whole body.
- Search reads the stored body, so collapsed text still matches.

Collapsed state lasts as long as the note stays open. Nothing is persisted, and
every region starts expanded when a note is opened again. Two breaks in a row,
or a break ending a note, leave a region with nothing in it, which renders as a
plain divider with no control rather than an empty thing to fold.

## List previews

Rows show a compact plain-text preview with Markdown syntax removed. Only the
opening fragment is parsed because the row can display only a small amount of
text. Whitespace is collapsed to a single line.

## Export contract

A note leaves the app in one of two forms, and the difference is deliberate.
Markdown export is the authored source, so it preserves the syntax the note is
stored as and can be edited again elsewhere. PDF export is a rendered document,
so it shows the note the way read mode shows it rather than exposing the syntax.
Neither replaces the other.

Both exporters accept injected locale and time-zone values so date output is
deterministic in tests, and both take only authored content: the title, the
event date when there is one, and the body. Creation and edit timestamps, folder
membership, pinned state, version history, and read-mode collapse state stay
private to application bookkeeping and reach neither format.

### Markdown file

The generated document contains:

1. The note title as a Markdown heading.
2. The event date, when present.
3. The stored body without rewriting it.
4. A text notice when a drawing is attached.

Drawings are not embedded in the Markdown file, because a Markdown document
cannot carry one without a companion image.

### PDF file

The generated document contains, in order:

1. The note title, then the event date when there is one, above a rule.
2. The body with its Markdown rendered: headings, bold, italic, inline code,
   links, ordered and unordered lists with nesting, block quotes, fenced code
   blocks, and thematic breaks.
3. The note's current drawing, when it has one.

The page is US Letter with a one inch margin, and long notes paginate across as
many pages as they need. The document is typeset rather than screenshotted, so
its text can be selected, searched, and printed at full quality, and the file
stays small. Only the drawing is an image.

A thematic break renders as a plain rule. Read mode's collapse controls are
interface, not content, so no chevron or collapsed marker appears in a PDF, and
the whole note is exported whatever is folded on screen at the time.

The PDF uses a light document appearance in both app appearances. A file meant
to be read, shared, and printed should not arrive with a dark background because
the app was in dark mode when it was exported.

Markdown links keep their styling and are written as real PDF links, so a reader
can follow them. Code blocks are set in a monospaced face on a tinted panel and
wrap long lines rather than running off the page. There is no syntax
highlighting.

A drawing is rasterized at the aspect ratio it was drawn in. One too tall for
the room left on a page moves to the next page, and one too tall for a whole
page is scaled to fit rather than cropped. A drawing that is empty, or whose
stored bytes no longer decode, is left out and the note's text still exports.
