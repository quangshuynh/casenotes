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

![All Notes showing a pinned note above a more recently edited one, a note
marked as carrying a drawing, folder names, and an event date](screenshots/notes-dark.png){ width="300" }

## Folders

Folders can be created, renamed, and deleted. All Notes and Unfiled are explicit
browsing scopes. A note belongs to at most one folder.

Deleting a folder does not delete its notes. SwiftData nullifies the
relationship, and the confirmation explains that affected notes move to
Unfiled.

![Folder list showing the All Notes and Unfiled scopes above three folders, each
with a note count](screenshots/library-dark.png){ width="300" }

## Drawing

A note can hold one PencilKit drawing. The drawing editor owns an in-progress
canvas, so Cancel discards changes and Done saves them. Saving a cleared canvas
removes the drawing record. Merely opening a drawing does not rewrite it or
change the note timestamp.

![PencilKit canvas holding a sketch, with the system tool picker along the
bottom and Cancel, Clear, and Done in the navigation bar](screenshots/drawing-dark.png){ width="300" }

The canvas keeps a light paper ground in either app appearance, so ink looks the
same while it is drawn and while it is read.

## Sharing and export

- Copy Note places the rendered Markdown document on the pasteboard without
  the CaseNotes footer, so a note pasted into other writing carries no wording
  the user did not write.
- Share Note sends Markdown text through the system share sheet.
- Export Markdown File creates a `.md` document through `Transferable`.

Exports include the title, optional event date, and body. App bookkeeping such
as creation time, edit time, and pinned state is omitted. A text line indicates
that a drawing exists because the drawing itself is not embedded.
