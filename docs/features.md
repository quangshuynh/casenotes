# Features

## Notes

Notes have a required nonblank title, Markdown body, creation and edit
timestamps, optional event date, pinned state, optional folder, and optional
drawing. Reading and editing are separate modes, so opening a note does not
modify it.

Editing uses an in-memory draft. Save applies the draft, while Cancel discards
it. Authored content changes update `updatedAt`; opening, closing, or moving a
note between folders does not.

The list supports title and body substring search, Last Updated and Date
Created ordering, and pinned-first grouping within either order.

## Folders

Folders can be created, renamed, and deleted. All Notes and Unfiled are explicit
browsing scopes. A note belongs to at most one folder.

Deleting a folder does not delete its notes. SwiftData nullifies the
relationship, and the confirmation explains that affected notes move to
Unfiled.

## Drawing

A note can hold one PencilKit drawing. The drawing editor owns an in-progress
canvas, so Cancel discards changes and Done saves them. Saving a cleared canvas
removes the drawing record. Merely opening a drawing does not rewrite it or
change the note timestamp.

## Sharing and export

- Copy Note places the stored Markdown source on the pasteboard.
- Share Note sends Markdown text through the system share sheet.
- Export Markdown File creates a `.md` document through `Transferable`.

Exports include the title, optional event date, and body. App bookkeeping such
as creation time, edit time, and pinned state is omitted. A text line indicates
that a drawing exists because the drawing itself is not embedded.
